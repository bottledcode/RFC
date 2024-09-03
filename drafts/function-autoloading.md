# PHP RFC: Function Autoloading v4

* Version: 1.0
* Date: 2024-08-15
* Author: Robert Landers, landers.robert@gmail.com
* Status: Under Discussion (or Accepted or Declined)
* First Published at: <http://wiki.php.net/rfc/function_autoloading4>

## Introduction

The topic of supporting function autoloading was brought up many times in the past, this RFC introduces a potential
implementation which would be consistent with what we have for autoloading classes.

By using autoloaders,
programmers can already get quickly up to speed when it comes to classes,
but the language currently lacks a way to do the same for functions.
This requires programmers to manually (and carefully) include files that must be included on every request.
For 'functional' codebases,
they lose the ability to use autoloaders, or they must write their functions as static methods on classes.
This isn’t ideal, and this RFC seeks to close the gap between functions and classes.

## Proposal

This RFC proposes to add two new constants to the SPL extension: `SPL_AUTOLOAD_CLASS`, `SPL_AUTOLOAD_FUNCTION`.
These constants may be passed to `spl_autoload_register` as the fourth parameter
to register an autoloader for classes or functions, respectively.
If not specified, the default value `SPL_AUTOLOAD_CLASS` will be used to retain backward compatibility.

There won’t be any changes to the current autoloading mechanism when it comes to classes.

### Function Autoloading

The function autoloader will be called with the fully qualified undefined function name.
This will allow the function autoloader to determine how to load or generate the function.

PHP allows programmers to call an unqualified function name.
Traditionally, this means that PHP would first search in the current namespace for the function
and then fall back to the global namespace if the function is not found.
This behavior will be preserved.
However, the function autoloader will be called **only once** for the current namespace;
thus, the function autoloader will not be called again if the function is found in the global namespace.

Example "`PSR-4-style`" (except the last part of the namespace is the file it is in) function autoloader:

```php
<?php

spl_autoload_register(function ($function, $type) {
    if ($type === SPL_AUTOLOAD_FUNCTION) {
        $function_path = dirname(str_replace('\\', DIRECTORY_SEPARATOR, $function));
        $file = __DIR__ . '/functions/' . $function_path . '.php';

        if (file_exists($file)) {
            require_once $file;
        }
    }
}, false, false, SPL_AUTOLOAD_FUNCTION);
```

### Performance Impact

Function autoloading doesn’t appear to have a significant impact on performance; however, the function autoloader itself
(depending upon its implementation) may have a performance impact.

To help mitigate any potential performance impact of function autoloading many unqualified functions,
a function will only be searched for once per namespace.

### spl_autoload

The `spl_autoload` function will not be modified.
It may be used as a function autoloader if the programmer desires,
though it will limit the programmer to a single function per file.

### spl_autoload_unregister

`spl_autoload_unregister` will be updated to accept the new constants as the second parameter to unregister an
autoloader from either mode.

### spl_autoload_functions

`spl_autoload_functions` will be updated to accept one of the new constants as the first parameter. Passing both (i.e.,
`SPL_AUTOLOAD_CLASS | SPL_AUTOLOAD_FUNCTION`) will result in all registered functions.

### spl_autoload_call

The `spl_autoload_call` function will be modified to accept a second parameter of one or both of the constants,
with the default value set to `SPL_AUTOLOAD_CLASS`.
The name of the first parameter will be changed to `$name` to reflect that it can be a class or function name.

In the event that both constants are passed, it will attempt to autoload both types.
This may be useful in the case where functions and invocable classes are used interchangeably.

```php
spl_autoload_call('Some\func', SPL_AUTOLOAD_FUNCTION); // Calls the function autoloader
spl_autoload_call('Some\func'); // Calls the class autoloader
spl_autoload_call('Some\func', SPL_AUTOLOAD_CLASS); // Calls the class autoloader
spl_autoload_call('func', SPL_AUTOLOAD_FUNCTION | SPL_AUTOLOAD_CLASS); // Calls both autoloaders with the name 'func'
```

### function_exists

The `function_exists` function will be updated to include a boolean option (`$autoload`) as the second parameter,
which will default to `true`.
If set to `true`, the function autoloader will be called if the function is not defined, otherwise, it will not be
called.

## Backward Incompatible Changes

There shouldn’t be any backward incompatible changes.

## Proposed PHP Version(s)

8.5 or later.

## RFC Impact

### To Opcache

- Potential changes to JIT helpers to call the autoloader instead of reading from the function table directly.

### New Constants

Two new constants will be added to the SPL extension: SPL_AUTOLOAD_CLASS, SPL_AUTOLOAD_FUNCTION.

## Open Issues

None.

## Future Scope

Potentially, constants and stream wrappers can be added in a similar fashion.

## Proposed Voting Choices

As per the voting RFC a yes/no vote with a 2/3 majority is needed for this proposal to be accepted.

Voting started on 2023-XX-XX and will end on 2023-XX-XX.

<!-- markdownlint-disable MD037 -->
<doodle title="Implement Function Autoloading v4, as described" auth="withinboredom" voteType="single" closed="true" closeon="2022-01-01T00:00:00Z">
   * Yes
   * No
</doodle>
<!-- markdownlint-disable MD037 -->

## Patches and Tests

Review the implementation [on GitHub #15471](https://github.com/php/php-src/pull/15471)

## Implementation

- Implentation: [PR #15471](https://github.com/php/php-src/pull/15471)
- Version: TBD
- PHP Manual Entry: TODO

## References

- [autofunc](https://wiki.php.net/rfc/autofunc): This heavily influenced this RFC. (declined in 2011)
- [function_autoloading](https://wiki.php.net/rfc/function_autoloading): This RFC was declined in 2011.
- [function_autoloading_v2](https://wiki.php.net/rfc/function_autoloading2): This RFC was declined in 2012.

Thank you for all of those that contributed to the discussions back then. I hope that this RFC will be successful.

## Rejected Features

### Autoloading constants

Autoloading of other types such as constants and stream wrappers will come in a later RFC.
