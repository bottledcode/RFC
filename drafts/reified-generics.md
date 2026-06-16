# PHP RFC: Reified Generics

- Version: 0.1
- Date: 2026-06-16
- Author: Robert Landers, landers.robert@gmail.com
- Status: Draft
- First Published at: <http://wiki.php.net/rfc/reified-generics>
- Implementation: <https://github.com/php/php-src/pull/XXXX>

## Introduction

This RFC proposes **reified generics** for PHP: type parameters on classes,
interfaces, traits, functions, methods, closures, and arrow functions, with
bounds, defaults, and variance, where the type arguments are **available at
runtime** rather than erased away.
A generic type parameter is written between angle brackets after the entity's
name, and the type arguments a caller supplies survive into the running program:
`new Box::<int>()` is genuinely an instance of `Box<int>`, `T::class` inside a
generic function yields the class that was actually supplied, and
`$x instanceof Box<int>` asks a real question with a real answer.

PHP has had erased, static-analysis-only generics in the ecosystem for years
through docblocks and tools like PHPStan and Psalm.
Those tools are excellent, but the type arguments vanish before the program
runs, so the language itself cannot use them: you cannot write `new T()`, you
cannot tell `List<int>` from `List<string>` at runtime, and a wrong type
argument is never an error unless a separate tool happens to be run.
This RFC closes that gap while keeping the runtime model simple and the
common-path cost close to zero.

```php
class Collection<T : object> {
    /** @var array<T> */
    private array $items = [];

    public function add(T $item): void { $this->items[] = $item; }
    public function first(): T { return $this->items[0]; }
    public function typeName(): string { return T::class; }
}

$users = new Collection::<User>();
$users->add(new User("Alice"));

echo $users->typeName();          // User
echo get_class($users);           // Collection<User>
var_dump($users instanceof Collection<User>);  // true
```

## Proposal

Generics are reified along **two axes**, depending on what declares the type
parameter:

- **Class-like generics are monomorphised.** Each distinct tuple of type
  arguments at a generic class, interface, or trait synthesises its own
  `class_entry`. `Box<int>` and `Box<string>` are distinct classes whose
  canonical names are spelled out (`"Box<int>"`, `"Box<string>"`) and
  registered in the class table. `get_class()`, `var_dump()`, and
  `instanceof Box<int>` all see the canonical monomorph.
- **Function- and method-level generics are reified per call frame.** Each
  call carries its own table mapping each type parameter to the class that was
  bound for it. There is no persistent `id<int>` function entry — that would
  grow without bound, so the binding lives on the frame and is consulted on
  demand. Closures and generators preserve the table so it survives suspension.

Everywhere an ordinary type-check happens — parameter coercion, return
verification, property writes — the engine checks against the type parameter's
declared **bound**, exactly as if no generics were involved. The reified type
arguments are kept on a side table and read only at a small number of
well-defined points (described below). This is what keeps non-generic code, and
the ordinary paths through generic code, fast.

### Declaring type parameters

A type parameter list is written in angle brackets directly after the name of
the entity that introduces it. The following declaration sites are supported:

```php
class Box<T> {}
interface Comparable<T> {}
trait Holder<T> {}

function id<T>(T $x): T { return $x; }

class Factory {
    public function build<T : object>(): T { return new T(); }
}

$closure = function <T>(T $x): T { return $x; };
$arrow   = fn<T>(T $x): T => $x;
```

Multiple parameters are comma-separated, and a trailing comma is permitted:

```php
class Map<K, V,> {}
```

Anonymous classes **cannot** declare type parameters:

```php
$x = new class<T> {};
// ParseError
```

A type parameter name must be unique within its declaration:

```php
class Bad<T, T> {}
// Fatal error: Cannot redeclare type parameter T
```

### Bounds

A bound constrains what a type argument may be, using `T : <type>`. The bound is
the type the engine enforces at ordinary parameter, return, and property slots.
A single class/interface, a union, an intersection, and full DNF are all
allowed:

```php
class A<T : Countable> {}              // single
class B<T : int|string> {}             // union
class C<T : Countable&Traversable> {}  // intersection
class D<T : (Countable&Traversable)|ArrayAccess> {}  // DNF
```

An unbounded type parameter is treated as `mixed` for type-check purposes (and,
where the bound is not expressible in the target slot — for example `callable`
on a property — the slot also falls back to `mixed`).

### Defaults

A type parameter may declare a default with `T = <type>`, used when the caller
supplies no argument for that position. A default must satisfy the bound, and
optional (defaulted) parameters may not precede required ones:

```php
class Box<T : object = stdClass> {}    // ok

class Bad1<T : object = int> {}
// Fatal error: Default int for type parameter T does not satisfy its bound object

class Bad2<T = int, U> {}
// Fatal error: Optional type parameter T cannot be declared before required type parameter U
```

### Variance

By default, a type parameter is **invariant**: `Box<Dog>` is not a `Box<Animal>`,
nor the reverse. A parameter may be marked **covariant** with `+T` (it may
appear only in "output" positions) or **contravariant** with `-T` (only in
"input" positions). The compiler verifies, at declaration time that every use
of the parameter respects its variance.

```php
interface Producer<+T> {          // covariant: T is produced, never consumed
    public function produce(): T;
}

interface Consumer<-T> {          // contravariant: T is consumed, never produced
    public function consume(T $value): void;
}
```

Covariant parameters may appear in return types, `readonly` properties, and
get-only hooked properties.
Contravariant parameters may appear in method parameters and set-only hooked
properties.
Read/write properties, get+set hooked properties, bounds, and defaults are
invariant positions.
Constructor parameters are exempt.
Polarity composes through nesting (outer × slot, with invariant absorbing), so a
covariant `T` used as the argument to a contravariant parameter lands in a
contravariant position. Violations are fatal at compile time:

```php
class Bad<+T> {
    public function take(T $x): void {}
}
// Fatal error: Type parameter T declared covariant (+T) cannot appear in contravariant position
```

The mirror message, `Type parameter T declared contravariant (-T) cannot appear
in covariant position`, applies to a `-T` used in a return type, and
`... cannot appear in invariant position` to either marker used in an invariant
slot.

### Recursive and mutual bounds

A bound may refer to the parameter it constrains, **as long as the reference is
nested inside another generic application** (F-bounded polymorphism). Two or
more parameters may refer to each other:

```php
interface Comparable<T> {
    public function compareTo(T $other): int;
}

// F-bound: T is constrained by a generic application that mentions T
function max<T : Comparable<T>>(T $a, T $b): T {
    return $a->compareTo($b) >= 0 ? $a : $b;
}

// Mutual bounds are allowed
class Pair<T : Box<U>, U : Box<T>> {}
```

A *direct* top-level self-reference is rejected because it constrains nothing:

```php
class Bad<T : T> {}
// Fatal error: Type parameter T cannot reference itself in its own bound or default
//              outside of a generic type argument
```

### Using a type parameter

Inside the body and signature of the declaring entity, a type parameter name is
a type. In signatures and property types it behaves as it's bound for ordinary
type-checking. In expression position it resolves, at runtime, to the class actually bound for the current frame (
function/method) or monomorph (class). Every `T`-keyed form is supported:

```php
function describe<T : object>($x): array {
    return [
        'new'        => new T(),          // instantiate the bound class
        'class'      => T::class,         // its name
        'const'      => T::SOME_CONST,    // a class constant
        'static'     => T::make(),        // a static call
        'instanceof' => $x instanceof T,  // an instance check
    ];
}
```

`catch (T $e)` is likewise supported. A type parameter used in a **static**
method signature or static property type is rejected because a static member
has no instance whose binding could be consulted:

```php
class A<T> {
    public static function foo(T $a): void {}
}
// Fatal error: Type parameter T is bound to A and cannot be used in static context
```

### Scalars, objects, and the class boundary

It is worth being explicit about where a type argument may be a scalar and where
it must be a class, because the line is deliberate and easy to miss.

**Type arguments themselves are unrestricted.** A scalar, union, intersection,
DNF, class, or nested generic application are all valid type arguments, in
turbofish and at use sites alike. Scalar arguments are not a degraded case: they
produce real monomorphs (`Box<int>` is a class) and they are **fully enforced**
at every ordinary type-check slot — parameter, return, property, and variadic:

```php
class Box<T> {
    public T $value;
}

$b = new Box::<int>();
$b->value = 42;            // ok
$b->value = "not-an-int";
// TypeError: Cannot assign string to property Box::$value of type int

function sum<T>(T ...$xs): T { /* ... */ }
sum::<int>(1, "abc", 3);
// TypeError: sum(): Argument #2 ($xs) must be of type int, string given
```

**The value-producing `T` forms require `T` to resolve to a class.** `new T()`,
`T::class`, `T::CONST`, and `T::method()` only make sense when `T` names a class
— there is no `new int()`, and `int` has no class entry to dispatch against. When
`T` resolves to a non-class (a scalar binding, or an unbounded `T` that fell back
to its non-class bound), these forms throw at runtime:

```php
function makeT<T>() { return new T(); }
makeT::<int>();
// Error: Cannot resolve generic type parameter T at runtime:
//        no binding was supplied and its bound is not a class
```

This is *by design*, not an incidental gap: the restriction is on the **operation**
(`new`/name/dispatch on a type that has no class), not on generics with scalar
arguments in general. In practice, code that uses these forms constrains the
parameter with an object bound — `class Factory<T : object>` or `T : SomeClass`
— which both documents the intent and lets the bound itself supply a meaningful
class when no argument is given. `instanceof T` and `catch (T $e)` do not throw
for a non-class `T`; since only objects can be instances or be thrown, a scalar
`T` simply never matches (`$scalar instanceof T` is `false`).

**Inference is object-only.** A bare type parameter is inferred only from an
*object* argument, never from a scalar; see [Inference](#inference) and
[Open Issues](#open-issues). This is the one place where the object restriction
is a genuine open design question rather than an inherent property of the
operation.

### Supplying type arguments

There are three ways a type argument reaches a generic entity: an explicit
**turbofish** at a call or `new`, a **type argument on a named type** at a use
site, and **inference** from an object argument.

#### Turbofish

At a call, instantiation, or first-class-callable site, type arguments are given
explicitly with `::<...>`:

```php
id::<int>(7);                 // function call
$obj->build::<User>();        // method call
$obj?->build::<User>();       // nullsafe call
Service::pick::<Dog>();       // static call
new Box::<int>(42);           // instantiation
$fn = id::<int>(...);         // first-class callable
```

Turbofish is also accepted on attributes:

```php
class Handler {
    #[Listens::<UserCreated>]
    public function onCreated(): void {}
}
```

Type arguments may be any type expression — a class, a scalar, a union, an
intersection, DNF, or a nested generic application such as `Box<Box<int>>`, as
well as `self`, `parent`, and `static` in a class context.

Two checks run at a turbofish site: **arity** and **bounds**. Supplying the
wrong number of arguments throws `ArgumentCountError`; an argument that violates
a bound throws `TypeError`:

```php
function f<T>($x) { return $x; }
f::<int, string>(1);
// ArgumentCountError: Too many generic type arguments to f(), 2 passed and exactly 1 expected

function need<T : Animal>(): void {}
need::<string>();
// TypeError: Type argument 1 to call need() does not satisfy the bound Animal on parameter T, string given
```

When the callee's body contains no `T`-keyed expression and the call is not an
instantiation, turbofish has no effect on the values flowing through — the type
arguments are validated, and then there is nothing for them to change.

#### Type arguments on named types

A generic type may be written with arguments wherever a type is expected — in
signatures, property types, `instanceof`, `catch`, and in `extends`,
`implements`, and `use` clauses:

```php
function sortable(Comparable<int> $c): void {}

class IntList extends Collection<int> {}
class Service implements Producer<User> {}
class IntHolder { use Holder<int>; }

$x instanceof Box<int>;
try { /* ... */ } catch (BoxedError<int> $e) { /* ... */ }
```

Writing type arguments on a class that is **not** generic is an error:

```php
class Plain {}
new Plain::<int>();
// Fatal error: Type arguments are not allowed on non-generic class Plain
```

#### Inference

When a function or method has a parameter whose declared type is *exactly* a
type parameter (`function id<T>(T $x)`), and the corresponding argument is an
**object**, `T` is inferred from that object's runtime class — no turbofish
required:

```php
class Foo { }
class Bar { }

function kind<T : object>(T $x): string { return T::class; }

echo kind(new Foo());   // Foo
echo kind(new Bar());   // Bar
```

If the same parameter appears in several positions, the first argument wins;
later arguments are checked against the bound but do not re-bind `T`.
Turbofish always overrides inference, and the substituted parameter type is then
enforced:

```php
kind::<Foo>(new Bar());
// TypeError: kind(): Argument #1 ($x) must be of type Foo, Bar given
```

The resolution order for a function/method type parameter is therefore:
**turbofish → inference (from an object argument) → default → the bound** (and
`mixed` if unbounded). Inference applies only to objects; binding a type
parameter from a *scalar* argument is intentionally left out of this proposal —
see [Open Issues](#open-issues). A scalar argument therefore does not pin `T`:
`kind(7)` leaves `T` to fall through to its default or bound, exactly as if the
argument had been omitted, which is why `T`-keyed forms in such a body need an
object bound to stay meaningful (see
[Scalars, objects, and the class boundary](#scalars-objects-and-the-class-boundary)).

### Reification

#### Monomorphised classes

Instantiating a generic class synthesises (or reuses) a distinct class entry
whose name is the canonical spelling of the application:

```php
class Box<T> {
    public function __construct(public mixed $value) {}
}

$a = new Box::<int>(1);
$b = new Box::<string>("x");

echo get_class($a);                       // Box<int>
echo get_class($b);                       // Box<string>
var_dump($a instanceof Box);              // true  (base is an ancestor)
var_dump($a instanceof Box<int>);         // true
var_dump($a instanceof Box<string>);      // false
var_dump(class_exists("Box<int>"));       // true  (synthesised on demand)
```

Canonical names sort the members of unions and intersections, so equivalent
shapes converge on a single monomorph; nested applications canonicalise
recursively, with no spaces:

```php
(new Box::<int|string>(0))::class === (new Box::<string|int>(0))::class;  // true → "Box<int|string>"
get_class(new Box::<Pair<int,string>>(...));                              // Box<Pair<int,string>>
```

Each monomorph is a real, independent class: it has its own static-property
storage, its own typed class constants (with `T` substituted), and is reachable
by name through `new $name()`, `class_exists()`, serialization, and Reflection.

#### Per-frame functions and methods

A generic function or method does not synthesise anything. The binding for its
type parameters lives on the call frame and is read on demand by the `T`-keyed
expressions in the body. Each frame — including each level of a recursive
call — has its own table, and closures and generators carry the table with them,
so it is still correct after suspension and resumption.

```php
function makeAdder<T : object>(): Closure {
    return fn() => T::class;     // captures this frame's binding for T
}

echo makeAdder::<Foo>()();   // Foo
echo makeAdder::<Bar>()();   // Bar
```

#### The bound view versus the reified shape

The two views serve two questions. The **bound** answers "what may a caller
pass at this slot", which is what the runtime type-checks and what Reflection's
`ReflectionType::getName()` reports. The **reified shape** answers "what was
actually supplied", which the `T`-keyed expressions consult and which Reflection
exposes separately. For an unbounded `T` the bound view is `mixed`; for
`Container<int>` the bound view is `Container`.

### Subtyping and assignability

Because each application of a generic class is its own monomorph, the obvious
question is how those monomorphs relate to one another: **is `Box<Tiger>`
acceptable where `Box<Animal>` is expected?** The answer follows the type
parameter's declared variance, and is enforced by the ordinary type-checker at
parameters, returns, and properties — there is no special generics path.

Every monomorph is a subclass of the unparameterised base, so a parameter typed
as the bare `Box` accepts *any* `Box<...>`. Among monomorphs of the same base,
assignability is decided per parameter:

- **Invariant `Box<T>` (the default):** only the exact same application is
  accepted. `Box<Tiger>` is **not** a `Box<Animal>`, and `Box<Animal>` is not a
  `Box<Tiger>`. The two are siblings under `Box`, not subtype and supertype.
- **Covariant `Box<+T>`:** assignability follows the argument. `Box<Tiger>`
  **is** a `Box<Animal>` (because `Tiger` is an `Animal`), but not the reverse.
- **Contravariant `Box<-T>`:** assignability is reversed. `Box<Animal>` is a
  `Box<Tiger>`, but not the reverse.

```php
class Animal {}
class Tiger extends Animal {}

class Box<T> {}                       // invariant
function feed(Box<Animal> $b): void {}

feed(new Box::<Animal>());            // ok — exact match
feed(new Box::<Tiger>());
// TypeError: feed(): Argument #1 ($b) must be of type Box<Animal>, Box<Tiger> given

class Covariant<+T> {}
function watch(Covariant<Animal> $c): void {}
watch(new Covariant::<Tiger>());      // ok — Tiger <: Animal, and +T is covariant
```

The same relation drives `instanceof`: with `Box<+T>`,
`new Box::<Tiger>() instanceof Box<Animal>` is `true`; with the invariant
default it is `false`. This is why the default is invariant — it is the only
choice that is sound for a container you can both read from and write to. A type
that is only ever read from can be marked `+T`; one that is only ever written to,
`-T`. The variance is checked once, at declaration (see [Variance](#variance)),
and from then on assignability is just subclassing between the synthesised
monomorphs, so the check at a call site costs no more than any other type check.

### Inheritance and substitution

When a class extends a generic ancestor or uses a generic trait with arguments,
the inherited property, method, and constant types are **substituted** with the
supplied bindings before the usual inheritance checks run:

```php
class Base<T> {
    public T $value;
    public function process(T $x): T { return $x; }
}

class IntBase extends Base<int> {}

$r = new ReflectionMethod(IntBase::class, 'process');
echo $r->getReturnType()->getName();          // int
(new IntBase)->process("nope");
// TypeError: ...process(): Argument #1 ($x) must be of type int, string given
```

A child may forward its own parameter into the ancestor (`class C<T> extends
Base<T> {}`), supply a concrete argument, or mix the two. Arity and bounds at
`extends`/`implements`/`use` are checked just as at any other use site, and LSP
(covariant returns, contravariant parameters) is verified against the
*substituted* parent signature. Where the same generic ancestor is reachable by
more than one path, the bindings must be consistent in arity; conflicting
concrete arguments are resolved through the normal per-implementer LSP checks.

### Reflection

Reflection is extended so that tooling can read the declaration and the supplied
arguments without reparsing the source. The bound view remains the default answer;
the reified shape is reachable through dedicated methods:

| Member                                                                 | Returns                                                                                                                         |
|------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------|
| `ReflectionClass::isGeneric()`                                         | whether the class/interface/trait declares type parameters                                                                      |
| `ReflectionClass::getGenericParameters()`                              | the declaration list (`ReflectionGenericTypeParameter[]`)                                                                       |
| `ReflectionClass::getGenericArgumentsForParentClass()`                 | arguments at the `extends` clause                                                                                               |
| `ReflectionClass::getGenericArgumentsForParentInterface(string $name)` | arguments at each `implements` path                                                                                             |
| `ReflectionClass::getGenericArgumentsForUsedTrait(string $name)`       | arguments at the `use` clause                                                                                                   |
| `ReflectionFunctionAbstract::isGeneric()` / `getGenericParameters()`   | for functions, methods, closures                                                                                                |
| `ReflectionNamedType::hasGenericArguments()` / `getGenericArguments()` | the reified arguments of an application, in source order                                                                        |
| `ReflectionNamedType::getName()`                                       | the bound's name (unchanged behaviour)                                                                                          |
| `ReflectionGenericTypeParameter`                                       | `getName()`, `getPosition()`, `getVariance()`, `hasBound()`/`getBound()`, `hasDefault()`/`getDefault()`, `getDeclaringEntity()` |
| `ReflectionTypeParameterReference`                                     | a `ReflectionType` that *is* a reference to a type parameter, appearing inside reified type expressions                         |
| `enum ReflectionGenericVariance`                                       | `Invariant`, `Covariant`, `Contravariant`                                                                                       |

```php
class Box<+T : object> {}

$p = new ReflectionClass('Box')->getGenericParameters()[0];
echo $p->getName();                 // T
echo $p->getVariance()->name;       // Covariant
echo $p->getBound()->getName();     // object
```

### Other runtime surfaces

`func_get_type_args()` returns the current frame's resolved type arguments as a
name-keyed array, reflecting turbofish, defaults, and inference together:

```php
function inspect<T : object, U : object = Foo>(T $x): array {
    return func_get_type_args();
}

inspect::<Foo, Bar>(new Foo());   // ['T' => 'Foo', 'U' => 'Bar']
inspect::<Bar>(new Bar());        // ['T' => 'Bar', 'U' => 'Foo']  (U defaulted)
inspect(new Bar());               // ['T' => 'Bar', 'U' => 'Foo']  (T inferred)
```

### Limits

An entity may declare at most 127 type parameters, and a use site may supply at
most 127 type arguments; exceeding either is a fatal error
(`Cannot declare more than 127 generic type parameters`, and the matching
message for arguments).

### Summary of rejections

| Situation                                             | Result                                                                                                    |
|-------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| Type parameter on an anonymous class                  | `ParseError`                                                                                              |
| Duplicate type parameter name                         | `Cannot redeclare type parameter T`                                                                       |
| Optional parameter before a required one              | `Optional type parameter T cannot be declared before required type parameter U`                           |
| Default that violates its bound                       | `Default <type> for type parameter T does not satisfy its bound <bound>`                                  |
| Direct self-reference in bound/default                | `Type parameter T cannot reference itself in its own bound or default outside of a generic type argument` |
| Variance violation                                    | `Type parameter T declared covariant (+T) cannot appear in contravariant position` (and mirrors)          |
| Class type parameter in static context                | `Type parameter T is bound to A and cannot be used in static context`                                     |
| Type arguments on a non-generic class                 | `Type arguments are not allowed on non-generic class Plain`                                               |
| Naked `new` of a class with a non-defaulted parameter | `Cannot instantiate generic class Box without type arguments; type parameter T has no default`            |
| Turbofish arity mismatch                              | `Too many/few generic type arguments to f(), N passed and ... expected`                                   |
| Turbofish bound violation                             | `Type argument 1 to call f() does not satisfy the bound <bound> on parameter T, <type> given`             |

## Performance

The guiding principle is **you pay for generics in proportion to how you use
them, and nothing if you don't**. Non-generic code emits none of the new
opcodes, allocates none of the side tables, and is byte-for-byte the interpreter
it is today. The paragraphs below describe where the cost actually lands. The
implementation is **correctness-first and not yet hand-optimised**, and several
of the costs below have clear room for improvement (noted as they come up).

### The steady-state cost is an ordinary type check

The single most important point is about *cost*, and it is easy to misread, so
to be unambiguous first: **a reified type check enforces the concrete bound type
— it is not skipped, and it does not silently widen to `mixed`.** Where a type
parameter is used in an enforced slot, the supplied argument is checked against
the reified type:

```php
class Box<T> {
    public function __construct(public T $value) {}
}

new Box::<int>('foo');
// TypeError: Cannot assign string to property Box::$value of type int

function id<T>(T $x): T { return $x; }
id::<int>('foo');
// TypeError: id(): Argument #1 ($x) must be of type int, string given
```

A value is accepted only when it actually satisfies the binding — or when the
author deliberately declared that slot wider than `T` (writing `mixed $value`
rather than `T $value`), in which case there is simply nothing about `T` to
enforce there, exactly as the author asked.

The performance claim is about how *expensive* that enforcement is, not about
what it accepts: a reified check reuses the **same type-comparison machinery as
any ordinary type check**, with no generics-specific branch in the hot path. So
enforcing `T = int` costs about what an ordinary `int` parameter costs;
enforcing `T : Foo` costs about what a `Foo` parameter costs; and an unbounded
`T` with no binding falls back to its `mixed` bound and costs what `mixed`
costs. In other words, you pay roughly what you would have paid had you written
the slot as `mixed` and checked the type by hand — the generic version is no
more expensive than that, while doing the check for you. Method dispatch on a
monomorph instance, and passing a monomorph to a typed parameter, likewise
resolve to a plain class and go through the normal class-compatibility machinery
once the class is in the table.

### Where time is paid

- **Monomorph synthesis** is the headline cost, and it is a **one-time,
  amortised** cost. The first `new Box::<int>()` in a request synthesises the
  `Box<int>` class entry — building the canonical name, linking it to the base,
  substituting inherited members, and running bound checks — and registers it in
  the class table. Every subsequent `new Box::<int>()`, `instanceof Box<int>`,
  or `Box<int>`-typed parameter is then a class-table lookup at pointer-compare
  speed. The cost is paid once per *distinct type-argument combination* per
  request, and opcache can persist synthesised monomorphs so it need not be
  repaid on every request.
- **Turbofish validation** (`ZEND_VERIFY_GENERIC_ARGUMENTS`) runs once per call
  that carries explicit type arguments, checking arity and bounds. It is a cold
  opcode emitted *only* where turbofish is written; under JIT it falls through to
  the interpreter (a known optimisation opportunity — the surrounding `INIT_*`
  and `ZEND_NEW` specialisations are unaffected).
- **Bare `T`-ref resolution** (`new T()`, `T::class`, `instanceof T`,
  `catch (T $e)`) is a small table lookup per use. The deferred
  `instanceof Box<T>` / `catch (Box<T>)` path caches its resolved class in a
  polymorphic inline cache keyed on the binding and scope, so a hot loop pays the
  resolution once and then hits a pointer compare; only thrashing the binding
  every iteration defeats the cache.
- **Inference** is deliberately cheap: for each unbound inferable parameter the
  engine reads the argument object's already-resolved class name. There is no
  unification, constraint solving, or extra compiler phase; the work is flat
  across class-hierarchy depth and parameter count, and tracks an explicit
  turbofish (and a plain call) closely.

### Where memory is paid

Measured on the proof-of-concept build:

- **No per-instance overhead.** A `Box<int>` instance is the same size as an
  instance of an equivalent non-generic class — the type arguments live on the
  class, not on every object.
- **About 1 KB per distinct monomorph** — roughly 1.5× the cost of a plain
  class-table entry — paid once per distinct combination and then cached for the
  request. This is the figure to budget against: an application that instantiates
  a few hundred distinct generic applications spends on the order of a few
  hundred kilobytes on their class entries.
- **No tax for generics you declare but don't instantiate.** A generic class
  *template* that is never applied costs essentially the same as a plain class
  declaration; the synthesis cost attaches to use, not to declaration.
- **Nesting does not multiply classes per level.** `Box<Box<Box<int>>>`
  materialises a full class entry for the instantiated outer monomorph; the inner
  levels are stored as lightweight type descriptors, so depth adds descriptor
  bytes rather than another full class each.

Synthesised monomorphs are request-scoped (or opcache-persisted), so they do not
accumulate across requests in a way that resembles a leak.

### Room for improvement

The numbers above reflect a first, correctness-oriented implementation. Synthesis
builds full class entries eagerly; the turbofish-verify opcode is not yet
JIT-specialised; canonical-name strings are rebuilt on the deferred-resolution
path before the cache is consulted. Each of these is a tractable optimisation
that can land after the semantics are settled, without changing any of the
behaviour described in this RFC.

## Backward Incompatible Changes

- This RFC introduces new syntax — type parameter lists, the `::<...>` turbofish,
  type arguments on named types, and variance markers — that does not collide
  with any existing valid PHP syntax. Code that does not use generics is
  unaffected.
- A new function `func_get_type_args()` is added to the global namespace. Code
  that already declares a userland function with this exact name in the global
  namespace would conflict; a search of public packages is part of the impact
  assessment below.
- Several Reflection classes gain methods and three new reflection types
  (`ReflectionGenericTypeParameter`, `ReflectionTypeParameterReference`, and the
  `ReflectionGenericVariance` enum) are introduced. Subclasses of the affected
  Reflection classes that already declare methods of the same names would
  conflict.
- Some error messages and Reflection output change for generic code only.
- Tooling that consumes the token stream or AST will need to learn the new
  syntax.

## Proposed PHP Version(s)

Next PHP 8.x.

## RFC Impact

### To the Ecosystem

Static analysers (PHPStan, Psalm) and IDEs already model erased generics through
docblocks; this RFC gives them a first-class syntax to read from, and Reflection
surfaces the declaration and the supplied arguments directly. Tools will want to
reconcile their existing docblock-based generics with the language-level form,
and auto-formatters, linters, and syntax highlighters will need to handle the
new syntax.

### To Existing Extensions

Extensions that build or introspect classes, functions, and types through the
internal APIs may need to account for the new per-entity generic metadata and
the monomorph class entries. Opcache is updated as part of the implementation to
persist the generic side tables and the captured turbofish arguments. No other
bundled extension is expected to require changes for correctness.

### To SAPIs

None.

### To Opcache

Generic metadata, monomorph synthesis inputs, and captured turbofish arguments
are persisted by opcache; these changes ship with the implementation. Code that
does not use generics emits none of the new opcodes or side tables.

## Open Issues

**Inference from scalar arguments.** In this proposal, a bare type parameter is
inferred only from an *object* argument — the value's runtime class becomes the
binding. A call like `id(7)` to `function id<T>(T $x): T` does **not** bind `T`
to `int`; `T` falls back to its default or bound. Whether (and how) to infer a
type parameter from a scalar argument is deliberately left open for discussion.
The questions that need answering before it could be added include:

- A scalar has no single "class" — what would `T::class` mean when `T` was
  inferred from `7`? Would `new T()` be meaningful at all?
- How would inference choose between `int` and `int|float` (or a wider bound)
  for a numeric literal, and would a later argument be allowed to widen it?
- Should scalar inference interact with coercion (would `id(7)` under weak typing
  ever bind `T` to `float`)?

This RFC's behaviour — object inference plus explicit turbofish — is complete and
useful on its own, and a future RFC can layer scalar inference on top without a
backward-incompatible change, since today those calls simply fall back to the
bound.

## Future Scope

- Scalar-argument inference (see Open Issues).
- Inferring class-level type arguments from constructor arguments
  (`new Collection([$a, $b])` deducing `Collection<...>`).
- Generic type aliases, building on a separate Type Aliases proposal.
- Variance shorthands or use-site variance beyond the declaration-site markers
  proposed here.

## Proposed Voting Choices

As this is a significant language change, a 2/3 majority is required.

<!-- markdownlint-disable MD037 -->
<doodle title="Implement Reified Generics, as described?" auth="withinboredom" voteType="single" closed="true" closeon="2026-01-01T00:00:00Z">
   * Yes
   * No
</doodle>
<!-- markdownlint-disable MD037 -->

## Patches and Tests

A proof-of-concept implementation exists, with an extensive `.phpt` suite under
`Zend/tests/generics/` covering declaration, bounds, defaults, variance,
recursive bounds, turbofish, monomorphisation, inheritance, reification,
scoping, reflection, traits, error cases, and limits.

Proof of concept: <https://github.com/php/php-src/pull/XXXX>

## Implementation

After the RFC is implemented, this section should contain:

1. the version(s) it was merged into
2. a link to the git commit(s)
3. a link to the PHP manual entry for the feature

## References

- [RFC: Type Aliases](https://wiki.php.net/rfc/type-aliases) (related type-system work)
- Prior generics discussions on php-internals

## Rejected Features

- **Fully erased generics** (type arguments discarded at compile time): rejected
  because it makes the type arguments unavailable to the language itself —
  no `new T()`, no runtime distinction between `List<int>` and `List<string>`,
  and no runtime enforcement.
- **Persistent function monomorphs** (`id<int>` as its own function entry):
  rejected because the set of instantiations is unbounded; function-level
  generics are reified per frame instead.

## Changelog

- 2026-06-16 v0.1: Initial draft.
