# PHP RFC: Inner Classes

* Version: 0.4
* Date: 2025-02-08
* Author: Rob Landers, rob@bottled.codes
* Status: Under Discussion (Accepted or Declined)
* First Published at: <http://wiki.php.net/rfc/short-and-inner-classes>

## Introduction

This RFC proposes a significant enhancement to the language: **Inner Classes**.
Inner classes enable the definition of classes within other classes,
introducing a new level of encapsulation and organization within PHP applications.

**Inner Classes** allows for the ability to define classes within other classes and control the use of inner classes
through visibility.
Many languages allow the encapsulation of behavior through inner classes (sometimes called **nested classes**),
such as Java, C#, and many others.

PHP developers currently rely heavily on annotations (e.g., @internal) or naming conventions to indicate encapsulation
of Data Transfer Objects (DTOs) and related internal classes.
These approaches offer limited enforcement, causing potential misuse or unintended coupling.

This RFC introduces Inner Classes to clearly communicate and enforce boundaries around encapsulated classes,
facilitating well-known design patterns (e.g., Builder, DTO, serialization patterns) with native language support.
This reduces boilerplate, enhances clarity, and ensures internal types remain truly internal.

## Proposal

Inner classes allow defining classes within other classes, following standard visibility rules.
This allows developers to declare a class as `private` or `protected` and restrict its usage to the outer class.
They are accessed via a new operator: `:>` which is a mixture of `->` and `::`.

```php
class Outer {
    public class Inner {
        public function __construct(public string $message) {}
    }
    
    private class PrivateInner {
        public function __construct(public string $message) {}
    }
}

$foo = new Outer:>Inner('Hello, world!');
echo $foo->message;
// outputs: Hello, world!
$baz = new Outer:>PrivateInner('Hello, world!');
// Fatal error: Class 'Outer:>PrivateInner' is private
```

Inner classes are just regular class definitions with a couple additional features.
That means,
except where otherwise noted, "how would inner classes work in situation X?"
can be answered with "the same as any other class/object."

### Declaration Syntax

Declaring an inner class is just like declaring any other class.
You can define `readonly`, `final`, and `abstract` inner classes -- or combinations, for example.
However, when defining an inner class, you may also define it as `private`, `protected`, or `public`.

If an inner class does not explicitly declare visibility (private, protected, or public),
it is implicitly considered public.
This matches PHP’s existing class behavior for methods and properties.

```php
class Outer {
    private class Inner {}
    protected readonly class ReadOnlyInner {}
    public abstract class AbstractInner {}
    public final class FinalInner {}
}
```

If an inner class is not defined as `private`, `protected`, or `public`, it is assumed to be `public`.

### Syntax rationale

The `:>` syntax was selected after evaluating alternatives:

- Using `::` was cumbersome and visually ambiguous due to existing static resolution syntax.
- Using `\` or `\\` was rejected due to potential conflicts with namespaces and escaping, causing confusion.

`:>` communicates "inner membership," visually linking the inner class to the outer class.

### Binding

Inner classes are explicitly bound to their outer classes and are intentionally not inherited through subclassing,
traits,
or interfaces.
This prevents ambiguity or complexity arising from inheriting tightly bound encapsulated logic.

```php
class Outer {
    class OuterInner {}
}

interface Foo {
    class FooInner {}
}

trait Bar {
    class BarInner {}
}

class All extends Outer implements Foo {
    use Bar;
    
    public function does_not_work() {
        new self:>OuterInner(); // Fatal error: Class 'All:>OuterInner' not found
        new self:>FooInner(); // Fatal error: Class 'All:>FooInner' not found
        new self:>BarInner(); // Fatal error: Class 'All:>BarInner' not found
        
        new parent:>OuterInner(); // This does work because it resolves to Outer:>OuterInner
    }
}
```

#### static resolution

The `static` keyword is **not** supported to resolve inner classes.
Attempting to do so results in an error, depending on where it is used:

```php
class Outer {
    class Inner {}
    
    // Fatal error: Cannot use the static modifier on a parameter
    public function foo(static:>Inner $bar) {}
    
    // Parse error: syntax error, unexpected token ":>", expecting ";" or "{"
    public function bar(): static:>Inner {}
    
    // Fatal error: Cannot use "static" as class name, as it is reserved 
    class Baz extends static:>Inner {}
    
    public function foobar() {
        return new static:>Inner(); // Fatal error: Cannot use the static modifier on an inner class
    }
}
```

This is to prevent casual LSP violations of inheritance and to maintain the strong binding of inner classes.

#### parent resolution

The `parent` keyword is supported to resolve inner classes. Which parent it resolves to depends on the context:

```php
class Foo {
    class Bar {}
}

class Baz extends Foo {
    // parent:>Bar resolves to Foo:>Bar
    class Bar extends parent:>Bar {
        // inside the class body, parent refers to Foo:>Bar
        public function doSomething(): parent {} 
    }
}
```

`parent` explicitly resolves to the parent class of the current class body it is written in and helps with writing more
concise code.

#### self resolution

The `self` keyword is supported to resolve inner classes. Which `self` it resolves to depends on the context:

```php
class Outer {
  class Middle {
    class Other {}
  
    // extends Outer:>Middle:>Other
    class Inner extends self:>Other {
        public function foo(): self {} // returns Outer:>Middle:>Inner
    }
  }
}
```

`self` explicitly resolves to the current class body it is written in, just like with `parent`.
On `inner` classes.

When using self inside a class body to refer to an inner class,
if the inner class is not found in the current class, it will fail with an error.

```php
class OuterParent {
    class Inner {}
    class Other {}
}

class MiddleChild extends OuterParent {
    // Fatal Error: cannot find class MiddleChild:>InnerParent
    class Inner extends self:>InnerParent {}
}

class OuterChild extends OuterParent {
    class Inner {}
    public function foo() {
        $inner = new self:>Inner(); // resolves to OuterChild:>Inner
        $inner = new parent:>Inner(); // resolves to OuterParent:>Inner
        $inner = new self:>Other(); // Fatal Error: cannot find class OuterChild:>Other
        $inner = new parent:>Other(); // resolves to OuterParent:>Other
    }
}
```

#### Dynamic resolution

Just as with `::`, developers may use variables to resolve inner classes,
or refer to them by name directly via a string:

```php
// Using variables to dynamically instantiate inner classes:
$outer = "Outer";
$inner = "Inner";
$instance = new $outer:>$inner();

// Instantiating inner class dynamically via a fully qualified class string:
$dynamicClassName = "Outer:>Inner";
$instance = new $dynamicClassName();

```

This provides flexibility and backwards compatibility for dynamic code that may not expect an inner class.

### Visibility from inner classes

Inner classes have access to their outer class’s private and protected methods, properties, and inner classes.
However, they do not have access to their siblings’ private and protected methods, properties, and inner classes.

```php
class User {
    public private(set) string $name;
    public private(set) string $email;
    
    private function __construct(self:>Builder $builder) {
        $this->name = $builder->name;
        $this->email = $builder->email;
    }
    
    public readonly final class Builder {
        public function __construct(public private(set) string|null $name = null, public private(set) string|null $email = null) {}
        
        public function withEmail(string $email): self {
            return new self($this->name, $email);
        }
        
        public function withName(string $name): self {
            return new self($name, $this->email);
        }
        
        public function build(): User {
            return new User($this);
        }
    }
}

$user = new User:>Builder()->withName('Rob')->withEmail('rob@bottled.codes')->build();
```

This enables usages such as builder patterns and other helper classes to succinctly encapsulate behavior.

### Visibility from outside the outer class

Inner classes are not visible outside their outer class unless they are public.
Protected classes may be used and accessed from within their child classes.

```php
class Outer {
    private class Other {}
    protected class Inner {
        public function Foo() {
            $bar = new Outer:>Inner(); // allowed
            $bar = new Outer:>Other(); // allowed
        }
    }
}

class SubOuter extends Outer {
    public function Foo() {
        $bar = new parent:>Inner(); // allowed to access protected inner class
        $bar = new parent:>Other(); // Cannot access private inner class 'Outer:>Other'
    }
}
```

Attempting to instantiate a private or protected inner class outside its outer class will result in a fatal error:

```php
new Outer:>Inner(); // Cannot access protected inner class 'Outer:>Inner'
```

#### Method return type and argument declarations

Inner classes may only be used as a return type or argument declarations for methods and functions
that have the same visibility or lesser.
Thus returning a `protected` class type from a `public` method is not allowed,
but is allowed from a `protected` or `private` method.

| Inner Class Visibility | Method Visibility | Allowed |
|------------------------|-------------------|---------|
| `public`               | `public`          | Yes     |
| `public`               | `protected`       | Yes     |
| `public`               | `private`         | Yes     |
| `protected`            | `public`          | No      |
| `protected`            | `protected`       | Yes     |
| `protected`            | `private`         | Yes     |
| `private`              | `public`          | No      |
| `private`              | `protected`       | No      |
| `private`              | `private`         | Yes     |

Methods and functions outside the outer class are considered public from the perspective of an inner class.
Attempting to declare a return of a non-visible type will result in a `TypeError`:

```php
class Outer {
    private class Inner {}
    
    public function getInner(): self:>Inner {
        return new self:>Inner();
    }
}

// Fatal error: Uncaught TypeError: Public method getInner cannot return private class Outer:>Inner
new Outer()->getInner();
```

#### Properties

The visibility of a type declaration on a property must also not increase the visibility of an inner class.
Thus, a public property cannot declare a private type.

This gives a great deal of control to developers, preventing accidental misuse of inner classes.
However, this **does not** preclude developers from returning a private/protected inner class,
only from using them as a type declaration.
The developer can use an interface or abstract class type declaration,
or use a broader type such as `object`, `mixed`, or nothing at all:

```php
class Outer {
    private class Inner implements FooBar {}
    
    public function getInner(): FooBar {
        return new self:>Inner(); // not an error
    }
}
```

### Accessing outer classes

Inner classes do not implicitly have access to an outer class instance.
This design choice avoids implicit coupling between classes and keeps inner classes simpler,
facilitating potential future extensions
(such as adding an explicit outer keyword) without backward compatibility issues.

Passing an outer instance explicitly remains an available option for accessing protected/private methods or properties.
Thus inner classes may access outer class private/protected methods and properties if given an instance.

```php
class Message {
    public function __construct(private string $message, private string $from, private string $to) {}
    
    public function Serialize(): string {
        return new Message:>SerializedMessage($this)->message;
    }
    
    private class SerializedMessage {
        public string $message;
        
        public function __construct(Message $message) {
            $this->message = strlen($message->from) . $message->from . strlen($message->to) . $message->to . strlen($message->message) . $message->message;
        }
    }
}
```

### Reflection

Several new methods are added to `ReflectionClass` to help support inspection of inner classes:

```php
$reflection = new ReflectionClass('\a\namespace\Outer:>Inner');

$reflection->isInnerClass(); // true
$reflection->isPublic() || $reflection->isProtected() || $reflection->isPrivate(); // true
$reflection->getName(); // \a\namespace\Outer:>Inner
$reflection->getShortName(); // Outer:>Inner
```

For non-inner classes, `ReflectionClass::isInnerClass()` returns false. 

### Autoloading

Inner classes are never autoloaded, only their outermost class is autoloaded.
If the outermost class does not exist, then their inner classes do not exist.

### Usage

Inner classes may be defined in the body of any class-like structure, including but not limited to:

- in a class body
- in an anonymous class body
- in an enum body
- in a trait body
- in an interface body

Note:
While traits and interfaces may define inner classes,
classes using these traits or implementing these interfaces do not inherit their inner classes.
Inner classes remain strictly scoped and bound to their defining context only.

### Outer class effects

Inner classes are fully independent of their outer class’s declaration modifiers.
Outer class modifiers such as abstract, final,
or readonly do not implicitly cascade down or affect the inner classes defined within them.

Specifically:

- An abstract outer class can define concrete (non-abstract) inner classes. Inner classes remain instantiable,
  independent of the outer class’s abstractness.
- A final outer class does not force its inner classes to be final. Inner classes within a final class can be extended
  internally, providing flexibility within encapsulation boundaries.
- A readonly outer class can define mutable inner classes. This supports internal flexibility, allowing the outer class
  to maintain immutability in its external API while managing state changes internally via inner classes.

Examples:

```php
abstract class Service {
    // Valid: Inner class is not abstract, despite the outer class being abstract.
    public class Implementation {
        public function run(): void {}
    }
}

// Allowed; abstract outer class does not force inner classes to be abstract.
new Service:>Implementation();
```

```php
readonly class ImmutableCollection {
    private array $items;

    public function __construct(array $items) {
        $this->items = $items;
    }

    public function getMutableBuilder(): self:>Builder {
        return new self:>Builder($this->items);
    }

    public class Builder {
        private array $items;

        public function __construct(array $items) {
            $this->items = $items;
        }

        public function add(mixed $item): self {
            $this->items[] = $item;
            return $this;
        }

        public function build(): ImmutableCollection {
            return new ImmutableCollection($this->items);
        }
    }
}
```

In this example, even though ImmutableBuilder is a mutable inner class within a readonly outer class,
the outer class maintains its immutability externally,
while inner classes help internally with state management or transitional operations.

### Abstract inner classes

It is worth exploring what an `abstract` inner class means and how it works.
Abstract inner classes are allowed to be the parent of any class that can see them.
For example, a private abstract class may only be inherited by subclasses in the same outer class.
A protected abstract class may be inherited by an inner class in a subclass of the outer class or an inner class in the
same outer class.
However, this is not required by subclasses of the outer class.

Abstract inner classes may not be instantiated, just as abstract outer classes may not be instantiated.

```php
class OuterParent {
    protected abstract class InnerBase {}
}

// Middle is allowed, does not have to implement InnerBase
class Middle extends OuterParent {}

// Last demonstrates extending the abstract inner class explicitly.
class Last extends OuterParent {
    private abstract class InnerExtended extends OuterParent:>InnerBase {}
}

```

## Backward Incompatible Changes

- This RFC introduces new syntax and behavior to PHP, which does not conflict with existing syntax.
- Some error messages will be updated to reflect inner classes, and tests that depend on these error messages are likely
  to fail.
- Tooling using AST or tokenization may need to be updated to support the new syntax.

## Proposed PHP Version(s)

This RFC targets the next version of PHP.

## RFC Impact

### To SAPIs

None.

### To Existing Extensions

Extensions accepting class names may need to be updated to support `:>` in class names.
None were discovered during testing, but it is possible there are unbundled extensions that may be affected.

### To Opcache

This change introduces a new opcode, AST, and other changes that affect opcache.
These changes are included as part of the PR that implements this feature.

### To Tooling

Tooling that uses AST or tokenization may need to be updated to support the new syntax,
such as syntax highlighting, static analysis, and code generation tools. 

## Open Issues

Pending discussion.

## Unaffected PHP Functionality

There should be no change to any existing PHP syntax.

## Future Scope

- Inner enums
- Inner interfaces
- Inner traits
- `Outer` keyword for easily accessing outer classes

## Proposed Voting Choices

As this is a significant change to the language, a 2/3 majority is required.

<!-- markdownlint-disable MD037 -->
<doodle title="Implement Short and Inner Classes, as described" auth="withinboredom" voteType="single" closed="true" closeon="2022-01-01T00:00:00Z">
   * Yes
   * No
</doodle>
<!-- markdownlint-disable MD037 -->

## Patches and Tests

To be completed.

## Implementation

After the project is implemented, this section should contain - the
version(s) it was merged into - a link to the git commit(s) - a link to
the PHP manual entry for the feature - a link to the language
specification section (if any)

## References

- [email that inspired this RFC](https://externals.io/message/125975#125977)
- [RFC: Records](https://wiki.php.net/rfc/records)

## Rejected Features

TBD
