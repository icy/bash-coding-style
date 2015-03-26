## Table of contents

* [Description](#description)
* [Author. License](#author-license)
* [Tabs and Spaces](#tabs-and-spaces)
* [Pipe](#pipe)
* [Variable names](#variable-names)
* [Function names](#function-names)
* [Error handling](#error-handling)
* [Pipe error handling](#pipe-error-handling)
* [Automatic error handling](#automatic-error-handling)
* [Catch up to $?](#catch-up-to-)
* [Good lessons](#good-lessons)

  * [2015: squid restarting remove system files](#2015-restarting-squid-31-on-a-rhel-system-removes-all-system-files)
  * [2015: steam removes everything](#2015-steam-removes-everything-on-system)
  * [2012: backup-manager kills a French company](#2012-backup-manager-kills-a-french-company)
  * [2012: a node manager remove system directories](#2012-n-a-node-version-manager-removes-system-directories)
  * [2011: a space removes everything under /usr/](#2011-a-space-that-removes-everything-under-usr)
  * [2001: itunes installer deletes hard drivers](#2001-itunes-20-installer-deletes-hard-drives)

## Description

This is a set of `Bash` coding conventions and good pratices.

The original Vietnamese version can be found here
  http://theslinux.org/doc/bash/coding_style/.
It is not up-to-date, though.

## Author. License

The author is Anh K. Huynh.

The work is released under a MIT license.

## Tabs and Spaces

Never use `(smart-)`tabs. Replace a tab by two spaces.

Do not accept any trailing spaces.

## Pipe

There are `inline` pipe and `display` pipe.  Unless your pipe is too
short, please use `display` pipe to make things clear.

Example

    This is an inline pipe: "$(ls -la /foo/ | grep /bar/)"

    # The following pipe is of display form: every command is on
    # its own line.

    _foobar="$( \
      ls -la /foo/ \
      | grep /bar/ \
      | awk '{print $NF}')"

When using `display` form, put pipe symbol (`|`) at the beginning of
of its statement. Never put `|` at the end of a line.

## Variable names

A variable is named according to its scope.

* If a variable can be changed from its parent environment,
  it should be in uppercase; e.g, `THIS_IS_A_USER_VARIABLE`.
* Other variables are in lowercase, started by an underscore;
  e.g, `_this_is_a_variable`. The primary purpose of the underscore (`_`)
  is to create a natural distance between the dollar (`$`)
  and the name when the variable is used (e.g, `$_this_is_a_variable`).
  This makes your code more readable, esp. when there isn't color support
  on your source code viewer.
* Any local variables inside a function definition should be
  declared with a `local` statement.

Example

    # The following variable can be provided by user at run time.
    D_ROOT="${D_ROOT:-}"

    # All variables inside `_my_def` are declared with `local` statement.
    _my_def() {
      local _d_tmp="/tmp/"
      local _f_a=
      local _f_b=

      # This is good, but it's quite a mess
      local _f_x= _f_y=
    }

Though `local` statement can declare multiple variables, that way
makes your code unreadable. Put each `local` statement on its own line.

## Function names

Name of internal functions should be started by an underscore (`_`).
Use underscore (`_`) to glue verbs and nouns. Don't use camel form
(`ThisIsBad`; use `this_is_not_bad` instead.)

## Error handling

All errors should be sent to `STDERR`. Never send any error/warning message
to a`STDOUT` device. Never use `echo` directly to print your message;
use a wrapper instead (`warn`, `err`, `die`,...). For example,

    _warn() {
      echo >&2 ":: $*"
    }

    _die() {
      echo >&2 ":: $*"
      exit 1
    }

Do not handle error of another function. Each function should handle
error and/or error message by their own implementation, inside its own
definition.

    _my_def() {
      _foobar_call

      if [[ $? -ge 1 ]]; then
        echo >&2 "_foobar_call has some error"
        _error "_foobar_call has some error"
        return 1
      fi
    }

In the above example, `_my_def` is trying to handle error for `_foobar_call`.
That's not a good idea. Use the following code instead

    _foobar_call() {
      # do something

      if [[ $? -ge 1 ]]; then
        _error "$FUNCNAME has some internal error"
      fi
    }

    _my_def() {
      _foobar_call || return 1
    }

## Pipe error handling

Pipe stores its components' return codes in the `PIPESTATUS` array.
This variable can be used only *ONCE* in the sub-`{shell,process}`
followed the pipe. Be sure you catch it up!

    echo test | fail_command | something_else
    local _ret_pipe=( ${PIPESTATUS[@]} )
    # from here, `PIPESTATUS` is not available anymore

When this `_ret_pipe` array contains something other than zero,
you should check if some pipe component has failed. For example,

    # Note:
    #   This function only works when it is invoked
    #   immediately after a pipe statement.
    _is_good_pipe() {
      echo "${PIPESTATUS[@]}" | grep -qE "^[0 ]+$"
    }

    _do_something | _do_something_else | _do_anything
    _is_good_pipe \
    || {
      echo >&2 ":: Unable to do something"
    }

## Automatic error handling

### Set -u

Always use `set -u` to make sure you won't use any undeclared variable.
This saves you from a lot of headaches and critical bugs.

Because `set -u` can't help when a variable is declared and set to empty
value, don't trust it twice.

### Set -e

Use `set -e` if your script is being used for your own business.

Be careful when shipping `set -e` script to the world. It can simply
break a lot of games. And sometimes you will shoot yourself in the foot.

Let's see

    set -e
    _do_some_critical_check

    if [[ $? -ge 1 ]]; then
      echo "Oh, you will never see this line"
    fi

If `_do_some_critical_check` fails, the script just exits and the following
code is just skipped without any notice. Too bad, right?

## Catch up to $?

`$?` is used to get the return code of the *last statement*.
To use it, please make sure you are not too late. The best way is to
save the variable to a local variable. For example,

    _do_something_critical
    local _ret="$?"
    # from now, $? is zero, because the latest statement (assignment)
    # (always) returns zero.

    _do_something_terrible
    echo "done"
    if [[ $? -ge 1 ]]; then
      # Bash will never reach here. Because "echo" has returned zero.
    fi

`$?` is very useful. But don't trust it.

## Good lessons

Some bad #bash error can kill a whole system. Here are some examples,
as food for your future vulnerabilities. They are good lessons, so please
learn them; don't criticize.

### 2015: Restarting `squid-3.1` on a `RHEL` system removes all system files

Reference: https://bugzilla.redhat.com/show_bug.cgi?id=1202858.

See discussion on Hacker News:
  https://news.ycombinator.com/item?id=9254876.

*Please note* that this is a bug catched by `QA` team, before
the package is released; that's a luck catch.
`RedHat` team should have fixed their `#bash` coding style.

The problem may come form a patch https://bugzilla.redhat.com/show_bug.cgi?id=1102343
that tries to clean up `squid`'s `PID` directory:

    restart() {
      stop
      RETVAL=$?
      if [ $RETVAL -eq 0 ] ; then
        rm -rf $SQUID_PIDFILE_DIR/*
        start
      ...
    }

That is similar to this script
  https://github.com/mozilla-services/squid-rpm/blob/47880414f17affdbb634b6f0a19a342995fb60f6/SOURCES/squid.init,
whose copy is in `examples/squid.init.sh`. Because `RedHat` doesn't publish
their code, we can only _guess_ that they put `SQUID_PIDFILE_DIR` in some
external configuration file (like `Debian` often uses `/etc/default/`),
and for some `UNKNOWN` reason, `$SQUID_PIDFILE_DIR` is expanded to `empty`.

### 2015: `Steam` removes everything on system

Reference: https://github.com/ValveSoftware/steam-for-linux/issues/3671.

The problem was introduced in the following commit:
  https://github.com/indrora/steam_latest/blob/21cc14158c171f5912b04b83abf41205eb804b31/scripts/steam.sh#L359
(a copy of this script can be found at `examples/steam.sh`.)

If the `steam.sh` script is invoked with `--reset` option, for example,
when there isn't `~/.steam/` directory, it will invoke the internal function
`reset_steam`, in which a `remove-all` command is instructed

    STEAMROOT="$(cd "${0%/*}" && echo $PWD)"
    # ...

    reset_steam() {
      # ...
      rm -rf "$STEAMROOT/"*
      # ...
    }

The bad thing happens when `$STEAMROOT` is `/` (when you have `/steam.sh`)
or just empty (when you execute `bash steam.sh`, `$0` is `steam.sh` and
the `cd` command just fails, results in an empty `$STEAMROOT`.)

Please note that using `set -u` doesn't help here. When `cd` command fails,
`$STEAMROOT` is empty and `set -u` sees no error. It's a problem with
working directory detection, and it's very very hard to do it right.
So forget it; and don't delete anything :)

### 2012: `Backup Manager` kills a French company

Reference: http://dragula.viettug.org/blogs/675.html.

This tool uses `$?` to check if an internal backup script fails.
Unfortunately, `$?` is used too late; hence the program always returns
successfully. In 2012, a French company lost all their database backups,
and that took down their internal tools in 1 month.

You can see the line `189` from the files `examples/backup_methods.sh`
for details. This file is shipped with `backup-manager` version `0.7.10.1-2`
on `Ubuntu 14.04-LTS`.

### 2012: `n`, a node version manager, removes system directories

Reference: https://github.com/tj/n/issues/86 .

There are a lot of funny `.gif`s in this `github` issue.
The code that causes the bug is here
  https://github.com/tj/n/pull/85/files.
A copy of the file is found at `examples/n.sh`.

The author assumes that `nodejs` is installed under `/usr/local/`.
You will find this at the beginning of the script

    VERSION="0.7.3"
    N_PREFIX=${N_PREFIX-/usr/local}
    VERSIONS_DIR=$N_PREFIX/n/versions

There is nothing wrong with this, until they decide to remove everything
under `$N_PREFIX`,

    install_node() {
      ....

        # symlink everything, purge old copies or symlinks
        for d in bin lib share include; do
          rm -rf $N_PREFIX/$d
          ln -s $dir/$d $N_PREFIX/$d
      ...
    }

It's clear that `/usr/local/lib/` (and similar directory) may contain
other system files.

### 2011: A space that removes everything under `/usr/`

Reference:
  https://github.com/MrMEEE/bumblebee-Old-and-abbandoned/commit/6cd6b2485668e8a87485cb34ca8a0a937e73f16d

See also https://github.com/MrMEEE/bumblebee-Old-and-abbandoned/issues/123.
A copy of `install.sh` file is `examples/bumblebee_install.sh`.

The author tries to clean up some directories

    rm -rf /usr /lib/nvidia-current/xorg/xorg

Unfortunately, because he "was very tired that night", he inserted an
extra space after `/usr`, and every one got bonus: buy one, get two.

This problem may (slightly) be avoided by using quoting, and listing.

### 2001: iTunes 2.0 Installer Deletes Hard Drives

Reference:
  http://apple.slashdot.org/story/01/11/04/0412209/itunes-20-installer-deletes-hard-drives

Anonymous quote: (http://apple.slashdot.org/comments.pl?sid=23365&cid=2518563)

> In the installer is a small shell script to remove any old copies of iTunes.
> It contained the following line of code:
>
>   rm -rf $2Applications/iTunes.app 2
>
> where "$2" is the name of the drive iTunes is being installed on.
>
> The problem is, since the pathname is not in quotes, if the drive name
> has a space, and there are other drives named similarly then the installer
> will delete the similarly named drive (for instance if your drives are:
> "Disk", "Disk 1", and Disk 2" and you install on "Disk 1"
> then the command will become "rm -rf Disk 1/Applications/iTunes.app 2
>
> The new updated version of the installer replaced that line of code with:
>
>   rm -rf "$2Applications/iTunes.app" 2
>   so things should work fine now.
