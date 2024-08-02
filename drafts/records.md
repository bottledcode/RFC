# PHP RFC: Records

- Version: 0.9
- Date: 2024-07-19
- Author: Robert Landers, landers.robert@gmail.com
- Status: Draft (or Under Discussion or Accepted or Declined)
- First Published at: <http://wiki.php.net/rfc/records>

## Introduction

This RFC proposes the introduction of `record` objects, which are immutable classes
with [value semantics](https://en.wikipedia.org/wiki/Value_semantics).

### Value objects

Value objects are immutable objects that represent a value.
They’re used to store values with a different semantic meaning than their technical value, adding additional context.
For example, a `Point` object with `x` and `y` properties can represent a point in a 2D space,
and an `ExpirationDate` can represent a date when something expires.
This prevents developers from accidentally using the wrong value in the wrong context.

Consider this example where a function accepts an integer as a user ID,
and the ID is accidentally set to a nonsensical value:

```php
function updateUserRole(int $userId, string $role): void {
    // ...
}

$user = getUser(/*...*/)
$uid = $user->id;
// ...
$uid = 5; // somehow accidentally sets uid to an unrelated integer
// ...
updateUserRole($uid, 'admin'); // accidental passing of a nonsensical value for uid
```

Currently, the only solution to this is to use a **class**, but this requires significant boilerplate code.
Further, **readonly classes** have many edge cases and are rather unwieldy.

#### The solution

Like arrays, strings, and other values, **record** objects are strongly equal (`===`) to each other if they contain the same
values.

Let’s take a look at the updated example, using a `record` type for `UserId`.
Thus, if someone were to pass an `int` to `updateUserRole`, it would throw an error:

```php
record UserId(int $id);

function updateUserRole(UserId $userId, string $role): void {
    // ...
}

$user = getUser(/*...*/)
$uid = $user->id; // $uid is a UserId object
// ...
$uid = 5;
// ...
updateUserRole($uid, 'admin'); // This will throw an error
```

Now, if `$uid` is accidentally set to an integer,
the call to `updateUserRole` will throw a `TypeError`
because the function expects a `UserId` object instead of a plain integer.

## Proposal

This RFC proposes the introduction of a `record` keyword in PHP to define immutable value objects. 
These objects will allow properties to be initialized concisely
and will provide built-in methods for common operations
such as modifying properties and equality checks using a function-like instantiation syntax.
Records can implement interfaces and use traits but can’t extend other records or classes;
composition is allowed, however.

### Syntax and semantics

#### Definition

A **record** is defined by the keyword `record`,
followed by the name of its type (e.g., `UserId`),
and then must list one or more typed parameters (e.g., `int $id`) that become properties of the record.
A parameter may provide `private` or `public` modifiers, but are `public` by when not specified.
This is referred to as the "inline constructor."

A **record** may optionally implement an interface using the `implements` keyword,
which may optionally be followed by a record body enclosed in curly braces `{}`.

A **record** may not extend another record or class.

A **record** may contain a traditional constructor with zero arguments to perform further initialization.

A **record** body may contain property hooks, methods, and use traits.

A **record** body may also declare properties whose values are only mutable during a constructor call.
At any other time, the property is immutable.

A **record** body may also contain static methods and properties,
which behave identically to static methods and properties in classes.
They may be accessed using the `::` operator.

``` php
namespace Paint;

// Define a record with several primary color properties
record Pigment(int $red, int $yellow, int $blue) {

  // property hooks are allowed
  public string $hexValue {
    get => sprintf("#%02x%02x%02x", $this->red, $this->yellow, $this->blue),
  }

  // methods are allowed
  public function mix(Pigment $other, float $amount): Pigment {
    return $this->with(
      red: $this->red * (1 - $amount) + $other->red * $amount,
      yellow: $this->yellow * (1 - $amount) + $other->yellow * $amount,
      blue: $this->blue * (1 - $amount) + $other->blue * $amount
    );
  }
  
  // all properties are mutable in constructors
  public function __construct() {
    $this->red = max(0, min(255, $this->red));
    $this->yellow = max(0, min(255, $this->yellow));
    $this->blue = max(0, min(255, $this->blue));
  }
  
  public function with() {
    // prevent the creation of a new Pigment from an existing pigment
    throw new \LogicException("Cannot create a new Pigment from an existing pigment");
  }
}

// simple records do not need to define a body
record StockPaint(Pigment $color, float $volume);

record PaintBucket(StockPaint ...$constituents) {
  public function mixIn(StockPaint $paint): PaintBucket {
    return $this->with(...[...$this->constituents, $paint]);
  }

  public function color(): Pigment {
    return array_reduce($this->constituents, fn($color, $paint) => $color->mix($paint->color, $paint->volume), Pigment(0, 0, 0));
  }
}
```

#### Usage

A record may be used as a readonly class,
as the behavior of the two is very similar once instantiated,
assisting in migrating from one implementation to another.

#### Optional parameters and default values

A `record` can also be defined with optional parameters that are set if omitted during instantiation.

One or more properties defined in the inline constructor may have a default value
declared using the same syntax and rules as any other default parameter declared in methods/functions.
If a property has a default value,
it is optional when instantiating the record, and PHP will assign the default value to the property.

``` php
record Rectangle(int $x, int $y = 10);
var_dump(Rectangle(10)); // output a record with x: 10 and y: 10
```

#### Auto-generated `with` method

To make records more useful, the RFC proposes generating a `with` method for each record.
This method allows for partial updates to the properties,
creating a new instance of the record with the specified properties updated.

##### How the with method works

**Named arguments**

The `with` method accepts only named arguments defined in the inline constructor.
Properties not defined in the inline constructor can’t be updated by this method.

**Variadic arguments**

Variadic arguments from the inline constructor don’t require named arguments in the `with` method.
However, mixing variadic arguments in the same `with` method call is not allowed by PHP syntax.

Using named arguments:

```php
record UserId(int $id) {
  public string $serialNumber;

  public function __construct() {
    $this->serialNumber = "U{$this->id}";
  }
}

$userId = UserId(1);
$otherId = $userId->with(2); // Fails: Named arguments must be used
$otherId = $userId->with(serialNumber: "U2"); // Error: serialNumber is not in the inline constructor
$otherId = $userId->with(id: 2); // Success: id is updated
```

Using variadic arguments:

```php
record Vector(int $dimensions, int ...$values);

$vector = Vector(3, 1, 2, 3);
$vector = $vector->with(dimensions: 4); // Success: values are updated
$vector = $vector->with(dimensions: 4, 1, 2, 3, 4); // Error: Mixing named and variadic arguments
$vector = $vector->with(dimensions: 4)->with(1, 2, 3, 4); // Success: First update dimensions, then values
```

##### Custom with method

A developer may define their own `with` method if they so choose,
and reference the generated `with` method using `parent::with()`.
This allows a developer to define policies or constraints on how data is updated.

Contravariance and covariance are enforced in the developer’s code:
- Contravariance: the parameter type of the custom `with` method must be a supertype of the generated `with` method.
- Covariance: the return type of the custom `with` method must be `self` of the generated `with` method.

``` php
record Planet(string $name, int $population) {
  // create a with method that only accepts population updates
  public function with(int $population): Planet {
    return parent::with(population: $population);
  }
}
$pluto = Planet("Pluto", 0);
// we made it!
$pluto = $pluto->with(population: 1);
// and then we changed the name
$mickey = $pluto->with(name: "Mickey"); // Error: no named argument for population
```

#### Constructors

A **record** has two types of constructors: the inline constructor and the traditional constructor.

The inline constructor is always required and must define at least one parameter.
The traditional constructor is optional and can be used for further initialization logic,
but mustn’t accept any arguments.

When a traditional constructor exists and is called,
the properties are already initialized to the value of the inline constructor
and are mutable until the end of the method, at which point they become immutable.

```php
// Inline constructor
record User(string $name, string $email) {
  public string $id;

  // Traditional constructor
  public function __construct() {
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
      throw new InvalidArgumentException("Invalid email address");
    }
    
    $this->id = hash('sha256', $email);
    $this->name = ucwords($name);
  }
}
```

### Mental models and how it works

From the perspective of a developer, declaring a record declares an object and function with the same name.
The developer can consider the record function (the inline constructor)
as a factory function that creates a new object or retrieves an existing object from an array.

For example, this would be a valid mental model for a Point record:

```php
record Point(int $x, int $y) {
    public function add(Point $point): Point {
        return Point($this->x + $point->x, $this->y + $point->y);
    }
}

// similar to declaring the following function and class

// used during construction to allow immutability
class Point_Implementation {
    public int $x;
    public int $y;

    public function __construct() {}

    public function with(...$parameters) {
        // validity checks omitted for brevity
        $parameters = array_merge([$this->x, $this->y], $parameters);
        return Point(...$parameters);
    }
    
    public function add(Point $point): Point {
        return Point($this->x + $point->x, $this->y + $point->y);
    }
}

interface Record {
    public function with(...$parameters): self;
}

// used to enforce immutability but has the same implementation
readonly class Point implements Record {
    public function __construct(public int $x, public int $y) {}

    public function with(...$parameters): self {
        // validity checks omitted for brevity
        $parameters = array_merge([$this->x, $this->y], $parameters);
        return Point(...$parameters);
    }
    
    public function add(Point $point): Point {
        return Point($this->x + $point->x, $this->y + $point->y);
    }
}

function Point(int $x, int $y): Point {
    static $points = [];
    // look up the identity of the point
    $key = hash_func($x, $y);
    if ($points[$key] ?? null) {
        // return an existing point
        return $points[$key];
    }

    // create a new point
    $reflector = new \ReflectionClass(Point_Implementation::class);
    $point = $reflector->newInstanceWithoutConstructor();
    $point->x = $x;
    $point->y = $y;
    $point->__construct();
    // copy properties to an immutable point and return it
    $point = new Point($point->x, $point->y);
    return $points[$key] = $point;
}
```

In reality, this is quite different from how it works in the engine,
but this provides a mental model of how behavior should be expected to work.
In other words, if it can work in the above model, then it be possible.

### Performance considerations

To ensure that records are both performant and memory-efficient,
the RFC proposes leveraging PHP’s copy-on-write (COW) semantics (similar to arrays) and interning values.
Unlike interned strings, the garbage collector will be allowed to clean up these interned records when they’re no
longer necessary.

``` php
$point1 = Point(3, 4);
$point2 = $point1; // No data duplication, $point2 references the same data as $point1
$point3 = Point(3, 4); // No data duplication, it is pointing to the same memory as $point1

$point4 = $point1->with(x: 5); // Data duplication occurs here, creating a new instance
```

#### Cloning and with()

Calling `clone` on a `record` results in the same record object being returned. As it is a "value" object, it
represents a value and is the same thing as saying `clone 3`—you expect to get back a `3`.

`with` may be called with no arguments, and it is the same behavior as `clone`.
This is an important consideration because a developer may call `$new = $record->with(...$array)` and we don’t want to
crash.
If a developer wants to crash, they can do by `assert($new !== $record)`.

### Serialization and deserialization

Records are fully serializable and deserializable.

```php
record Single(string $value);
record Multiple(string $value1, string $value2);

echo $single = serialize(Single('value')); // Outputs: "O:6:"Single":1:{s:5:"value";s:5:"value";}"
echo $multiple = serialize(Multiple('value1', 'value2')); // Outputs: "O:8:"Multiple":1:{s:6:"values";a:2:{i:0;s:6:"value1";i:1;s:6:"value2";}}"

echo unserialize($single) === Single('value'); // Outputs: true
echo unserialize($multiple) === Multiple('value1', 'value2'); // Outputs: true
```

### Equality

A `record` is always strongly equal (`===`) to another record with the same value in the properties,
much like an `array` is strongly equal to another array containing the same elements.
For all intents, `$recordA === $recordB` is the same as `$recordA == $recordB`.

Comparison operations will behave exactly like they do for classes, for example:

```php
record Time(float $milliseconds = 0) {
    public float $totalSeconds {
        get => $this->milliseconds / 1000,
    }
    
    public float $totalMinutes {
        get => $this->totalSeconds / 60,
    }
    /* ... */
}

$time1 = Time(1000);
$time2 = Time(5000);

echo $time1 < $time2; // Outputs: true
```

### Type hinting

A `\Record` interface will be added to the engine to allow type hinting for records.
All records implement this interface.

```php
function doSomething(\Record $record): void {
    // ...
}
```

The only method on the interface is `with`, which is a variadic method that accepts named arguments and returns `self`.

### Reflection

A new reflection class will be added to support records:
`ReflectionRecord` which will inherit from `ReflectionClass` and add a few additional methods:

- `ReflectionRecord::finalizeRecord(object $instance): Record`: Finalizes a record under construction, making it immutable.
- `ReflectionRecord::isRecord(mixed $object): bool`: Returns `true` if the object is a record, and `false` otherwise.
- `ReflectionRecord::getInlineConstructor(): ReflectionFunction`: Returns the inline constructor of the record as `ReflectionFunction`.
- `ReflectionRecord::getTraditionalConstructor(): ReflectionMethod`: Returns the traditional constructor of the record as `ReflectionMethod`.
- `ReflectionRecord::makeMutable(Record $instance): object`: Returns a new record instance with the properties mutable.
- `ReflectionRecord::isMutable(Record $instance): bool`: Returns `true` if the record is mutable, and `false` otherwise.

Using `ReflectionRecord` will allow developers to inspect records, their properties, and methods,
as well as create new instances for testing or custom deserialization.

Attempting to use `ReflectionClass` or `ReflectionFunction` on a record will throw a `ReflectionException` exception.

#### finalizeRecord()

The `finalizeRecord()` method is used to make a record immutable and look up its value in the internal cache,
returning an instance that represents the finalized record.

Calling `finalizeRecord()` on a record that has already been finalized will return the same instance.

#### isRecord()

The `isRecord()` method is used to determine if an object is a record. It returns `true` if the object is a record,

#### getInlineConstructor()

The `getInlineConstructor()` method is used to get the inline constructor of a record as a `ReflectionFunction`.
This can be used to inspect inlined properties and their types.

#### getTraditionalConstructor()

The `getTraditionalConstructor()` method is used
to get the traditional constructor of a record as a `ReflectionMethod`.
This can be useful to inspect the constructor for further initialization.

#### makeMutable()

The `makeMutable()` method is used to create a new instance of a record with mutable properties.
The returned instance doesn’t provide any value semantics
and should only be used for testing purposes or when there is no other option.

A mutable record can be finalized again using `finalizeRecord()` and to the engine, these are regular classes.
For example, `var_dump()` will output `object` instead of `record`.

#### isMutable()

The `isMutable()` method is used
to determine if a record has been made mutable via `makeMutable()` or otherwise not yet finalized.

#### Custom deserialization example

In cases where custom deserialization is required,
a developer can use `ReflectionRecord` to manually construct a new instance of a record.

```php
record Seconds(int $seconds);

$example = Seconds(5);

$reflector = new ReflectionRecord(ExpirationDate::class);
$expiration = $reflector->newInstanceWithoutConstructor();
$expiration->seconds = 5;
assert($example !== $expiration); // true
$expiration = $reflector->finalizeRecord($expiration);
assert($example === $expiration); // true
```

### var_dump

When passed an instance of a record the `var_dump()` function will output the same
as if an equivalent object were passed —
e.g., both having the same properties — except the output generated will replace the prefix text "object"
with the text "record."

```txt
record(Point)#1 (2) {
  ["x"]=>
  int(1)
  ["y"]=>
  int(2)
}
```

### Considerations for implementations

A `record` cannot share its name with an existing `record`, `class`, or `function` because defining a `record` creates
both a `class` and a `function` with the same name.

### Autoloading

This RFC chooses to omit autoloading from the specification for a record.
The reason is that instantiating a record calls the function
implicitly declared when the record is explicitly declared,
PHP doesn’t currently support autoloading functions,
and solving function autoloading is out-of-scope for this RFC.

Once function autoloading is implemented in PHP at some hopeful point in the future,
said autoloader could locate the record and then autoload it.

The author of this RFC strongly encourages someone to put forward a function autoloading RFC if autoloading is desired
for records.

## Backward Incompatible Changes

To avoid conflicts with existing code,
the `record` keyword will be handled similarly to `enum` to prevent backward compatibility issues.

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

To-do

## Unaffected PHP Functionality

None.

## Future Scope

## Proposed Voting Choices

Include these so readers know where you’re heading and can discuss the
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
