# PHP RFC: Inner Classes with Short Syntax

* Version: 0.1
* Date: 2025-02-08
* Author: Rob Landers, rob@bottled.codes
* Status: Draft (or Under Discussion or Accepted or Declined)
* First Published at: <http://wiki.php.net/rfc/short-and-inner-classes>

## Introduction

PHP has steadily evolved to enhance developer productivity and expressiveness,
introducing new features such as typed properties, constructor property promotion, and first-class callable syntax.
However, defining simple data structures and organizing classes remains verbose.

This RFC proposes two related enhancements to PHP:

**Short class syntax**, which allows for defining simple or data-oriented classes in a single line:

```php
class Point(int $x, int $y);
```

This syntax serves as a shorthand for defining classes with constructor property promotion,
reducing boilerplate while maintaining clarity.

**Inner classes**, which allows for the ability to define classes within other classes and control the use of inner classes through visibility:

```php
class Foo {
    public class Bar(public string $message);
}
```

## Proposal

### Short Class Syntax

The proposed syntax for a short class definition is as follows: a keyword `class`,
followed by the class name, then a list of properties enclosed in parentheses.
Optionally, a list of traits, interfaces, and a parent class may be defined.

```php

// a simple class with two public properties: x and y
class Point(int $x, int $y);

// a more complex readonly class with a parent class, interface, and traits.
readonly class Vector(int $x, int $y) extends BaseVector implements JsonSerializable use PointTrait, Evolvable;
```

This is equivalent to the following full class definition:

```php
class Point {
    public function __construct(public int $x, public int $y) {}
}

readonly public class Vector extends BaseVector implements JsonSerializable {
    use PointTrait, Evolvable;
    
    public function __construct(public int $x, public int $y) {}
}
```

Any properties defined within the parenthesis are defined as a property on the class
and are automatically `public` unless specified otherwise.

```php
// declare $shapes as a private property
class Geometry(private $shapes) use GeometryTrait;
```

#### Default Values

Default values may be provided for properties but only for properties with type hints:

```php
class Point(int $x = 0, int $y = 0);
```

#### Inheritance and Behavior

With class short syntax, no behavior may be defined, yet it can still utilize traits, interfaces, and other classes.

```php
class Point(int $x, int $y) extends BasePoint implements JsonSerializable use PointTrait, Evolvable;
```

Note that the original constructor from any parent class is overridden and not called by the short syntax.

#### Empty Classes

Short classes may also be empty:

```php
class Point() extends BasePoint use PointTrait;
```

#### Attributes

Attributes may also be used with short classes:

```php
#[MyAttribute]
class Password(#[SensitiveParameter] string $password);
```

#### Modifiers

Short classes support modifiers such as `readonly`, `final` and `abstract`:

```php
readonly class User(int $id, string $name);

final class Config(string $key, mixed $value);

abstract class Shape(float $area);
```

#### How it works

Short classes are implemented as pure syntax sugar and are compiled as full class definitions.

### Inner Classes

Inner classes are classes that are defined within another class.

```php
class Outer {
    class Inner(public string $message);
    
    private class PrivateInner {
        public function __construct(public string $message) {}
    }
}

$foo = new Outer::Inner('Hello, world!');
echo $foo->message;
// outputs: Hello, world!
$baz = new Outer::PrivateInner('Hello, world!');
// Fatal error: Uncaught Error: Cannot access private inner class Outer::PrivateInner 
```

Inner classes have inheritance similar to static properties, allowing you to define rich class hierarchies:

```php
readonly class Point(int $x, int $y);

class Geometry {
    public array $points;
    protected function __construct(Point ...$points) {
        $this->points = $points;
    }
    
    public class FromPoints extends Geometry {
        public function __construct(Point ...$points) {
            parent::__construct(...$points);
        }
    }
    
    public class FromCoordinates extends Geometry {
        public function __construct(int ...$coordinates) {
            $points = [];
            for ($i = 0; $i < count($coordinates); $i += 2) {
                $points[] = new Point($coordinates[$i], $coordinates[$i + 1]);
            }
            parent::__construct(...$points);
        }
    }
}

class Triangle extends Geometry {
    protected function __construct(public Point $p1, public Point $p2, public Point $p3) {
        parent::__construct($p1, $p2, $p3);
    }
    
    public class FromPoints extends Triangle {
        public function __construct(Point $p1, Point $p2, Point $p3) {
            parent::__construct($p1, $p2, $p3);
        }
    }
    
    public class FromCoordinates extends Triangle {
        public function __construct(int $x1, int $y1, int $x2, int $y2, int $x3, int $y3) {
            parent::__construct(new Point($x1, $y1), new Point($x2, $y2), new Point($x3, $y3));
        }
    }
}

$t = new Triangle::FromCoordinates(0, 0, 1, 1, 2, 2);

var_dump($t instanceof Triangle); // true
var_dump($t instanceof Geometry); // true
var_dump($t instanceof Triangle::FromCoordinates); // true
```

#### Modifiers

Inner classes support modifiers such as `public`, `protected`, `private`, `final` and `readonly`.
When using these as modifiers on an inner class, there are some intuitive rules:

- `public`, `private`, and `protected` apply to the visibility of the inner class.
- `final`, and `readonly` apply to the class itself.

Thus, an inner class with the modifier `private readonly` is only accessible within the class
and any instances are readonly.

`static` is not allowed as a modifier on an inner class because there is currently no such thing as a `static` class in PHP.

#### Visibility

A `private` or `protected` inner class type is only accessible within the class it is defined in
(or its subclasses in the case of protected classes).
This is similar to C#, so you may return a private type from a public method,
but not use it as a type hint from outside the outer class:

```php
class Outer {
    private class PrivateInner(string $message);
    
    public function getInner(): self::PrivateInner {
        return new self::PrivateInner('Hello, world!');
    }
}

// using a private inner class from outside the outer class, as a type hint is forbidden
function doSomething(Outer::PrivateInner $inner) {
    echo $inner->message;
}

// this is ok:
$inner = new Outer()->getInner();

// but this is not:
doSomething($inner);
// Fatal error: Private inner class Outer::Inner cannot be used in the global scope
```

Just like with other languages that support inner classes,
it is better to return an interface or a base class from a method instead of exposing a private/protected class.

You may also not instantiate a private/protected class from outside the outer class’s scope:

```php
$x = new Outer::PrivateInner();
// Fatal error: Uncaught Error: Cannot access private inner class Outer::Inner
```

#### Inheritance

Classes may not inherit from inner classes. Inner classes may inherit from other classes, including the outer class.

#### Names

Inner classes may not have any name that conflicts with a constant or static property of the same name.

```php
class Foo {
    const Bar = 'bar';
    class Bar(public string $message);
    
    // Fatal error: Uncaught Error: Cannot redeclare Foo::Bar
}

class Foo {
    static $Bar = 'bar';
    class Bar(public string $message);
    
    // Fatal error: Uncaught Error: Cannot redeclare Foo::$Bar
}
```

## Backward Incompatible Changes

This RFC introduces new syntax and behavior to PHP, which does not conflict with existing syntax.
However, tooling utilizing AST or tokenization may need to be updated to support the new syntax.

## Proposed PHP Version(s)

This RFC targets the next version of PHP.

## RFC Impact

### To SAPIs

None.

### To Existing Extensions

Extensions accepting class names may need to be updated to support `::` in class names.
None were discovered during testing, but it is possible there are extensions that may be affected.

### To Opcache

Most of the changes are in compilation and AST, so the impact to opcache is minimal.

## Open Issues

Pending discussion.

## Unaffected PHP Functionality

There should be no change to existing PHP functionality.

## Future Scope

- inner enums

## Proposed Voting Choices

<!-- markdownlint-disable MD037 -->
<doodle title="Implement Short and Inner Classes, as described" auth="withinboredom" voteType="single" closed="true" closeon="2022-01-01T00:00:00Z">
   * Yes
   * No
</doodle>
<!-- markdownlint-disable MD037 -->

## Patches and Tests

A complete implementation is available [on GitHub](https://github.com/php/php-src/compare/master...bottledcode:php-src:rfc/short-class2?expand=1).

## Implementation

After the project is implemented, this section should contain - the
version(s) it was merged into - a link to the git commit(s) - a link to
the PHP manual entry for the feature - a link to the language
specification section (if any)

## References

Links to external references, discussions or RFCs

## Rejected Features

Keep this updated with features that were discussed on the mail lists.
