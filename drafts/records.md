# PHP RFC: Records

- Version: 0.9
- Date: 2024-07-19
- Author: Robert Landers, landers.robert@gmail.com
- Status: Draft (or Under Discussion or Accepted or Declined)
- First Published at: <http://wiki.php.net/rfc/records>

## Introduction

This RFC proposed the introduction of `record` objects, which are immutable classes
with [value semantics](https://en.wikipedia.org/wiki/Value_semantics).

### Value objects

Value objects are immutable objects that represent a value. They are used to store values with a different meaning than
their technical value.
For example, a `Point` object with `x` and `y` properties can represent a point in a 2D space,
and an `ExpirationDate` can represent a date when something expires.
This prevents developers from accidentally using the wrong value in the wrong context.

Consider this example:

```php
function updateUserRole(int $userId, Role $role): void {
    // ...
}

$user = getUser(/*...*/)
$uid = $user->id;
// ...
$uid = 5; // somehow accidentally sets uid to an unrelated integer
// ...
updateUserRole($uid, Role::ADMIN()); // accidental passing of 
```

In this example, the uid is accidentally set to a plain integer, and updateUserRole is called with the wrong value.

Currently, the only solution to this is to use a class, but this requires a lot of boilerplate code.

#### The solution

Like arrays, strings, and other values, `record` objects are strongly equal to each other if they contain the same
values.

Let's take a look, using the previous example:

```php
record UserId(int $id);

function updateUserRole(UserId $userId, Role $role): void {
    // ...
}

$user = getUser(/*...*/)
$uid = $user->id; // $uid is a UserId object
// ...
$uid = 5;
// ...
updateUserRole($uid, Role::ADMIN()); // This will throw an error
```

## Proposal

This RFC proposes the introduction of a new record keyword in PHP to define immutable data objects. These objects will
allow properties to be initialized concisely and will provide built-in methods for common operations such as modifying
properties and equality checks using a function-like instantiation syntax.
Records can implement interfaces and use traits but cannot extend other records or classes;
composition is allowed, however.

#### Syntax and semantics

##### Definition

A `record` is defined by the word "record", followed by the name of its type, an open parenthesis containing one or more
typed parameters that become public, immutable, properties.
They may optionally implement an interface using the `implements` keyword.
A `record` body is optional.

A `record` may contain a constructor with zero arguments to perform further initialization, if required.
If it does not have a constructor, an implicit, empty contstructor is provided.

A `record` body may contain property hooks, methods, and use traits (so long as they do not conflict with `record`
rules).
Regular properties may also be defined, but they are immutable by default and are no different from `const`.

Static properties and methods are forbidden in a `record` (this includes
`const`, a regular property may be used instead). Attempting to define
static properties, methods, constants results in a compilation error.

``` php
namespace Paint;

record Pigment(int $red, int $yellow, int $blue) {
  public function mix(Pigment $other, float $amount): Pigment {
    return $this->with(
      red: $this->red * (1 - $amount) + $other->red * $amount,
      yellow: $this->yellow * (1 - $amount) + $other->yellow * $amount,
      blue: $this->blue * (1 - $amount) + $other->blue * $amount
    );
  }
}

record StockPaint(Pigment $color, float $volume);

record PaintBucket(StockPaint ...$constituents) {
  public function mixIn(StockPaint $paint): PaintBucket {
    return $this->with(...$this->constituents, $paint);
  }
  
  public function color(): Pigment {
    return array_reduce($this->constituents, fn($color, $paint) => $color->mix($paint->color, $paint->volume), Pigment(0, 0, 0));
  }
}
```

##### Usage

A `record` may be used as a `readonly class`,
as the behavior of it is very similar with no key differences to assist in migration from `readonly class`.

##### Optional parameters and default values

A `record` can also be defined with optional parameters that are set if left out during instantiation.

``` php
record Rectangle(int $x, int $y = 10);
var_dump(Rectangle(10)); // output a record with x: 10 and y: 10
```

##### Auto-generated `with` method

To enhance the usability of records, the RFC proposes automatically generating a `with` method for each record.
This method allows for partial updates of properties, creating a new instance of the record with the specified
properties updated.

The auto-generated `with` method accepts only named arguments defined in the constructor.
No other property names can be used, and it returns a new record object with the given values.

``` php
$point1 = Point(3, 4);
$point2 = $point1->with(x: 5);
$point3 = $point1->with(null, 10); // must use named arguments

echo $point1->x; // Outputs: 3
echo $point2->x; // Outputs: 5
```

A developer may define their own `with` method if they so choose,
and reference the generated `with` method using `parent::with()`.
This allows a developer to define policies or constraints on how data is updated.

``` php
record Planet(string $name, int $population) {
  public function with(int $population) {
    return parent::with(population: $population);
  }
}
$pluto = Planet("Pluto", 0);
// we made it!
$pluto = $pluto->with(population: 1);
// and then we changed the name
$mickey = $pluto->with(name: "Mickey"); // no named argument for population error
```

##### Constructors

Optionally, they may also define a constructor to provide validation or other initialization logic:

```php
record User(string $name, string $email) {
  public string $id;

  public function __construct() {
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
      throw new InvalidArgumentException("Invalid email address");
    }
    
    $this->id = hash('sha256', $email);
    $this->name = ucwords($name);
  }
}
```

During construction, a `record` is fully mutable.
This allows the developer freedom to mutate properties as needed to ensure a canonical representation of an object.

#### Performance considerations

To ensure that records are both performant and memory-efficient,
the RFC proposes leveraging PHP's copy-on-write (COW) semantics (similar to arrays) and interning values.
Unlike interned strings, the garbage collector will be allowed to clean up these interned records when they are no
longer needed.

``` php
$point1 = Point(3, 4);
$point2 = $point1; // No data duplication, $point2 references the same data as $point1
$point3 = Point(3, 4); // No data duplication here either, it is pointing the the same memory as $point1

$point4 = $point1->with(x: 5); // Data duplication occurs here, creating a new instance with modified data
```

##### Cloning and with()

Calling `clone` on a `record` results in the exact same record object being returned. As it is a "value" object, it
represents a value and is the same thing as saying `clone 3`—you expect to get back a `3`.

`with` may be called with no arguments, and it is the same behavior as `clone`.
This is an important consideration because a developer may call `$new = $record->with(...$array)` and we don’t want to
crash.
If a developer wants to crash, they can do by `assert($new !== $record)`.

#### Equality

A `record` is always strongly equal (`===`) to another record with the same value in the properties,
much like an `array` is strongly equal to another array containing the same elements.
For all intents, `$recordA === $recordB` is the same as `$recordA == $recordB`.

Comparison operations will behave exactly like they do for classes.

### Reflection

Records in PHP will be fully supported by the reflection API,
providing access to their properties and methods just like regular classes.
However, immutability and special instantiation rules will be enforced.

#### ReflectionClass support

`ReflectionClass` can be used to inspect records, their properties, and methods. Any attempt to modify record properties
via reflection will throw an exception, maintaining immutability. Attempting to create a new instance via
`ReflectionClass` will cause a `ReflectionException` to be thrown.

``` php
$point = Point(3, 4);
$reflection = new \ReflectionClass($point);

foreach ($reflection->getProperties() as $property) {
    echo $property->getName() . ': ' . $property->getValue($point) . PHP_EOL;
}
```

#### Immutability enforcement

Attempts to modify record properties via reflection will throw an exception.

``` php
try {
    $property = $reflection->getProperty('x');
    $property->setValue($point, 10); // This will throw an exception
} catch (\ReflectionException $e) {
    echo 'Exception: ' . $e->getMessage() . PHP_EOL; // "Cannot modify a record property"
}
```

#### ReflectionFunction for implicit constructor

Using `ReflectionFunction` on a record will reflect the implicit constructor.

``` php
$constructor = new \ReflectionFunction('Geometry\Point');
echo 'Constructor Parameters: ';
foreach ($constructor->getParameters() as $param) {
    echo $param->getName() . ' ';
}
```

#### New functions and methods

- Calling `is_object($record)` will return `true`.
- A new function, `is_record($record)`, will return `true` for records, and `false` otherwise
- Calling `get_class($record)` will return the record name

#### var_dump

Calling `var_dump` will look much like it does for objects, but instead of `object` it will say `record`.

    record(Point)#1 (2) {
      ["x"]=>
      int(1)
      ["y"]=>
      int(2)
    }

### Considerations for implementations

A `record` cannot be named after an existing `record`, `class` or `function`. This is because defining a `record`
creates both a `class` and a `function` with the same name.

### Auto loading

As invoking a record value by its name looks remarkably similar to calling a function,
and PHP has no function autoloader, auto loading will not be supported in this implementation.
If function auto loading were to be implemented in the future, an autoloader could locate the `record` and autoload it.
The author of this RFC strongly encourages someone to put forward a function auto loading RFC if auto loading is desired for records.

## Backward Incompatible Changes

No backward incompatible changes.

## Proposed PHP Version(s)

PHP 8.5

## RFC Impact

### To SAPIs

N/A

### To Existing Extensions

N/A

### To Opcache

Unknown.

### New Constants

None

### php.ini Defaults

None

## Open Issues

Todo

## Unaffected PHP Functionality

None.

## Future Scope

## Proposed Voting Choices

Include these so readers know where you are heading and can discuss the
proposed voting options.

## Patches and Tests

TBD

## Implementation

After the project is implemented, this section should contain

1. the version(s) it was merged into
2. a link to the git commit(s)
3. a link to the PHP manual entry for the feature
4. a link to the language specification section (if any)

## References

Links to external references, discussions or RFCs

## Rejected Features

Keep this updated with features that were discussed on the mail lists.
