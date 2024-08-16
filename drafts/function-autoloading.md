# PHP RFC: Function Autoloading v4

* Version: 1.0
* Date: 2024-08-15
* Author: Robert Landers, landers.robert@gmail.com
* Status: Under Discussion (or Accepted or Declined)
* First Published at: <http://wiki.php.net/rfc/function_autoloading4>

## Introduction

The topic of supporting function autoloading was brought up many times in the past, this RFC introduces a potential
implementation which would be consistent with what we have for autoloading classes.

## Proposal

Before getting into the details,
there are a few terms worth acknowledging so that the proposal can be easily discussed without getting confused:

1. **Defined function**: A function that the engine has knowledge of, such as in a previously included/required file.
2. **Undefined function**: A function that the engine does not have knowledge of.
3. **Function autoloading**: The process of loading a function that is not defined.
4. **Written function**: A function that exists in a file that the engine may or may not have knowledge of.
5. **Local scope**: The current namespace
6. **Global scope**: The global namespace (`\`)

The suggested change would be pretty straightforward and backwards-compatible:

1. Add two new constants to spl: SPL_AUTOLOAD_CLASS, SPL_AUTOLOAD_FUNCTION.
2. Add a fourth optional parameter for spl_autoload_register, with a default value of SPL_AUTOLOAD_CLASS.
3. The type for the missing token should also be passed to the $autoload_function callback as a second param. (e.g.,
   SPL_AUTOLOAD_CLASS for classes, SPL_AUTOLOAD_FUNCTION for functions)
4. Change the current class autoloading to only call the autoloaders which match with the SPL_AUTOLOAD_CLASS types.
5. Add the function autoloading to only call the autoloaders which match with the SPL_AUTOLOAD_FUNCTION types.

There won’t be any changes to the current autoloading mechanism when it comes to classes.
However, if a function

1. is called in a fully qualified form (e.g., a `use` statement or `\` prefix is used),
2. is not defined,
3. and an autoloader is registered with the SPL_AUTOLOAD_FUNCTION type

then the autoloader will be called with the function name as the first parameter (with the initial slash removed) and
SPL_AUTOLOAD_FUNCTION as the second parameter.

However, if a function

1. is called in an unqualified form (e.g., `strlen()`),
2. is not defined locally
3. and an autoloader is registered with the SPL_AUTOLOAD_FUNCTION type

then the autoloader will be called with the current namespace prepended to the function name.
If the autoloader chooses to look up the "basename" of the function, it may do so.
If the function is still undefined in the local scope,
then it will fall back to the global scope—unless the local scope is the global scope.
The function autoloader will not be called again.

This provides an opportunity
for an autoloader to check for the existence of a function in the local scope and define it,
as well as defer to the global scope if it is not defined.

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

Performance-wise, this should have minimal impact on existing codebases as there is no default function autoloader.

For codebases that want to take advantage of function autoloading,
it may be desirable to stick with FQNs for functions and/or employ caches and other techniques where possible. 

### spl_autoload

The `spl_autoload` function will not be updated.
For backwards compatibility,
there will be no changes to class autoloading and there will not be a default function autoloader.

### spl_autoload_call

The `spl_autoload_call` function will be modified to accept a second parameter of one,
(but not both) of the new constants,
with the default value set to SPL_AUTOLOAD_CLASS.
The name of the first parameter will be changed to `$name` to reflect that it can be a class or function name.

```php
spl_autoload_call('\Some\func', SPL_AUTOLOAD_FUNCTION); // Calls the function autoloader
spl_autoload_call('\Some\func'); // Calls the class autoloader
spl_autoload_call('Some\func', SPL_AUTOLOAD_CLASS); // Calls the class autoloader
spl_autoload_call('Some\func'); // Calls the class autoloader
spl_autoload_call('func', SPL_AUTOLOAD_FUNCTION | SPL_AUTOLOAD_CLASS); // Error: Cannot autoload multiple types
```

If the user wants to call multiple autoloaders, they can do so manually.


### function_exists

The `function_exists` function will be updated to include a boolean option (`$autoload`) as the second parameter,
which will default to `true`.
If set to `true`, the function autoloader will be called if the function is not defined, otherwise, it will not be called.

## Backward Incompatible Changes

There are no backward incompatible changes.

## Proposed PHP Version(s)

8.5 or later.

## RFC Impact

### To Opcache

To be determined.

### New Constants

Two new constants will be added to the SPL extension: SPL_AUTOLOAD_CLASS, SPL_AUTOLOAD_FUNCTION.

## Open Issues

To be determined.

## Future Scope

Potentially, constants and stream wrappers can be added in a similar fashion.

## Proposed Voting Choices

<doodle title="Implement Function Autoloading v4, as described" auth="withinboredom" voteType="single" closed="true" closeon="2022-01-01T00:00:00Z">
   * Yes
   * No
</doodle>

## Patches and Tests

Not yet.

## Implementation

After the project is implemented, this section should contain - the
version(s) it was merged into - a link to the git commit(s) - a link to
the PHP manual entry for the feature - a link to the language
specification section (if any)

## References


- [autofunc](https://wiki.php.net/rfc/autofunc): This heavily influenced this RFC. (declined in 2011)
- [function_autoloading](https://wiki.php.net/rfc/function_autoloading): This RFC was declined in 2011.
- [function_autoloading_v2](https://wiki.php.net/rfc/function_autoloading2): This RFC was declined in 2012.

Thank you for all of those that contributed to the discussions back then. I hope that this RFC will be successful.

## Rejected Features

Keep this updated with features that were discussed on the mail lists.
