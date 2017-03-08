## Table of contents

Some bad #bash error can kill a whole system. Here are some examples,
as food for your future vulnerabilities. They are good lessons, so please
learn them; don't criticize.

* [2015: squid restarting removes system files](#2015-restarting-squid-31-on-a-rhel-system-removes-all-system-files)
* [2015: steam removes everything](#2015-steam-removes-everything-on-system)
* [2012: backup-manager kills a French company](#2012-backup-manager-kills-a-french-company)
* [2012: a node manager removes system directories](#2012-n-a-node-version-manager-removes-system-directories)
* [2011: a space removes everything under /usr/](#2011-a-space-that-removes-everything-under-usr)
* [2001: itunes installer deletes hard drivers](#2001-itunes-20-installer-deletes-hard-drives)

## 2015: Restarting `squid-3.1` on a `RHEL` system removes all system files

*Lesson*: Removing something is always dangerous.

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

## 2015: `Steam` removes everything on system

*Lesson*: Removing something is always dangerous.

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

## 2012: `Backup Manager` kills a French company

*Lesson*: Save `$?` as soon as possible.

Reference: http://dragula.viettug.org/blogs/675.html.

This tool uses `$?` to check if an internal backup script fails.
Unfortunately, `$?` is used too late; hence the program always returns
successfully. In 2012, a French company lost all their database backups,
and that took down their internal tools in 1 month.

You can see the line `189` from the files `examples/backup_methods.sh`
for details.

*Update*:

1. This file is shipped with `backup-manager` version `0.7.10.1-2`
  on `Ubuntu 14.04-LTS`.
1. The tool with the same version and bad script is shipped with `Ubuntu 16.04-LTS`.

## 2012: `n`, a node version manager, removes system directories

*Lesson*: Removing something is always dangerous.

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

## 2011: A space that removes everything under `/usr/`

*Lesson*: Quoting is important. Quote what you think!

Reference:
  https://github.com/MrMEEE/bumblebee-Old-and-abbandoned/commit/6cd6b2485668e8a87485cb34ca8a0a937e73f16d

See also https://github.com/MrMEEE/bumblebee-Old-and-abbandoned/issues/123.
A copy of `install.sh` file is `examples/bumblebee_install.sh`.

The author tries to clean up some directories

    rm -rf /usr /lib/nvidia-current/xorg/xorg

Unfortunately, because he "was very tired that night", he inserted an
extra space after `/usr`, and every one got bonus: buy one, get two.

This problem may (slightly) be avoided by using quoting, and listing.

## 2001: iTunes 2.0 Installer Deletes Hard Drives

*Lesson*: Quoting is important. Quote what you think!

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
