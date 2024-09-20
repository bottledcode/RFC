# PHP RFC: Typed Aliases

* Version: 1.0
* Date: 2024-09-06
* Author: Robert Landers, landers.robert@gmail.com
* Status: Under Discussion (or Accepted or Declined)
* First Published at: <http://wiki.php.net/rfc/typed-aliases>

## Introduction

There are many times when you may need to write out a union/intersection type many times in PHP. This can be cumbersome and
error-prone.
This RFC proposes a new "typed alias"
syntax that will allow for the creation of type aliases that may be used project-wide.

Here is a brief example:

```php

namespace MyLibrary;

class Second {}
class Minute {}
class Hour {}

alias Time: Second|Minute|Hour;

// in another file

use MyLibrary\Time;
```

## Proposal

This RFC proposes to implement type aliases as a "special"
class type (similar to final, abstract, etc.) under the hood of the same name as its alias.
Thus, the alias `Time`, in the above example, would be a class named `Time` in the namespace `MyLibrary`.
This prevents collisions with other classes and defined "types" in the same namespace.

When the engine sees a class with this special type, it expands the alias into its actual type,
and continues with type checking.

### Aliases Classes

There are several classes of aliases:

1. **primitive** - An alias for a single primitive data type (int, float, string, bool, array, etc.)
2. **simple** - An alias for a single class or interface
3. **complex** - An alias for a union or intersection of other types

### Creating Aliases

An alias is defined by the work `alias`, followed by the alias name, a colon, and then the type to alias:

```php
alias Time: Second|Minute|Hour;
alias Number: int|float;
alias Stringy: string|Stringable;
alias Matrix: array;
alias Client: HttpClient&JsonClient;
```

### Using Aliases

Since an alias is essentially a class, under the hood, it can be used in the same way as a class.
This allows you to define an alias in one part of a project and use it in another:

```php
namespace MyProject;

use MyLibrary\Time;
use MyLibrary\Number;
use MyLibrary\Stringy;

function sleepFor(Time $time) {}

function retryTimes(Number $times) {}

function logMessage(Stringy|string $message) {} // Not a fatal error
```

#### Intersections and Unions

A type alias may be a union or intersection of other types (including other aliases),
even if they contain the same types in their alias.
It will not be a fatal error as it currently is when a type is a union or intersection with itself.
This allows libraries to declare type aliases that are specific to their own library
and be reused in other projects that may also have similar aliases.
For example,
a library may define a `Stringy` alias that is a union of `string`
and `Stringable` and another library may define a `ConstantString` alias
that is also a union of `Stringable` and `string`.
A project using both libraries would be able
to use `Stringy` and `ConstantString` in its own type alias or function type.

```php
alias Stringy: string|Stringable;
alias ConstantString: string|Stringable;

function logMessage(Stringy|ConstantString $message) {} // Not a fatal error
```

#### Nesting

Aliases may also be aliases of other aliases:

```php
namespace MyLibrary;

alas Time: Second|Minute|Hour;
alias Duration: Time|int;
```

#### Argument Lists and Return Types

The primary usage for aliases is in argument lists, instanceof and return types:

```php
use MyLibrary\Time;

function sleep(Time $time): Time {}

class Alarm {
    public function __construct(Time $time) {
        assert($time instanceof Time);
    }
    
    public function getTime(): Time {}
}
```

#### Extending and Implementing

For simple aliases of other classes, `type_alias` behaves exactly like `class_alias` and `autoload` set to `false`.
Thus, these types of aliases can be used in class extension and implementation:

```php
class A {}

alias B: A;

class C extends B {}
```

However, trying to extend or implement a complex or primitive alias will result in the expected fatal error:

```php
class A {}
class B {}

alias C: A|B;
alias D: int;

class E extends C {} // Fatal error: cannot extend a complex type alias
class F implements D {} // Fatal error: cannot implement a primitive type alias 
```

#### Calling new on Aliases

Aliases may be used in the `new` keyword, but only if the alias is a simple alias of a class, as is currently possible:

```php
class A {}

alias B: A; // same as calling class_alias('A', 'B');

new B();
```

#### Static calls on Aliases

Aliases may be used in static calls, but only if the alias is a simple alias of a class, as is currently possible:

```php
class A {
    public static function test() {}
}

alias B: A; // same as calling class_alias('A', 'B');

B::test();
```

## Reflection

It will be possible to use reflection to determine the type of alias.
When using `ReflectionClass` on an alias, it will see an object with one of the following base classes:

- `PrimitiveTypeAlias`
- `ComplexTypeAlias`

These classes will have the following structure:

```php

enum PrimitiveType {
    case int;
    case float;
    case string;
    case bool;
    case array;
    case object;
    case callable;
    case iterable;
    case void;
    case null;
}

abstract class PrimitiveTypeAlias {
    public const PrimitiveType $aliasOf;
}

abstract class ComplexTypeAlias {
    public const ReflectionType $aliasOf;
}
```

For simple aliases, using ReflectionClass will return the original class name, just like with `class_alias`.

Developers may access the `aliasOf` property to find out the alias’s underlying type.

## Why Special Classes?

After looking at the current type system in PHP,
it became clear that if we were to implement aliases in the existing type system,
it would be overly complex and challenging to maintain.
Using classes, however, is much simpler, easier to maintain, and debug.
It is also easier to reason about in the symbol tables as well
since classes are synonymous with types in lay-terms.

## Backward Incompatible Changes

There should be no backward incompatible changes.

## Proposed PHP Version(s)

8.5 or later.

## RFC Impact

### To SAPIs

N/A

### To Existing Extensions

N/A

### To Opcache

TBD

### New Constants

Describe any new constants so they can be accurately and comprehensively
explained in the PHP documentation.

### php.ini Defaults

If there are any php.ini settings then list: \* hardcoded default values
\* php.ini-development values \* php.ini-production values

## Open Issues

Make sure there are no open issues when the vote starts!

## Unaffected PHP Functionality

List existing areas/features of PHP that will not be changed by the RFC.

This helps avoid any ambiguity, shows that you have thought deeply about
the RFC's impact, and helps reduces mail list noise.

## Future Scope

This section details areas where the feature might be improved in
future, but that are not currently proposed in this RFC.

## Proposed Voting Choices

Include these so readers know where you are heading and can discuss the
proposed voting options.

## Patches and Tests

Links to any external patches and tests go here.

If there is no patch, make it clear who will create a patch, or whether
a volunteer to help with implementation is needed.

Make it clear if the patch is intended to be the final patch, or is just
a prototype.

For changes affecting the core language, you should also provide a patch
for the language specification.

## Implementation

After the project is implemented, this section should contain - the
version(s) it was merged into - a link to the git commit(s) - a link to
the PHP manual entry for the feature - a link to the language
specification section (if any)

## References

Links to external references, discussions or RFCs

## Rejected Features

Keep this updated with features that were discussed on the mail lists.
