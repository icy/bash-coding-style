#!/bin/bash

cat 1>&2 <<-EOF
  This script is not to run on any system.
  Anh K. Huynh adds this banner to prevent script from being used.

  The script is part of the backup-manager-0.7.10.1-2 on Ubuntu 14.04-LTS.
  It's here as an example of wrong use of $? in Bash.
EOF

exit 0

# Copyright (C) 2010 The Backup Manager Authors
#
# See the AUTHORS file for details.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# Every method to manage backup are here.
# We should give here as more details we can
# on the specific conffiles to use for the methods.
#

# This should be called whenever an archive is made, it will dump some
# informations (size, md5sum) and will add the archive in .md5 file.
function commit_archive()
{
    file_to_create="$1"
    size=$(size_of_path $file_to_create)
    str=$(echo_translated "\$file_to_create: ok (\${size}M,")
    debug "commit_archive ($file_to_create)"

    # The archive is ok, we can drop the "pending" stuff
    debug "rm -f ${bm_pending_incremental_list}.orig"
    rm -f "${bm_pending_incremental_list}.orig"
    bm_pending_incremental_list=""
    bm_pending_archive=""

    base=$(basename $file_to_create)
    md5hash=$(get_md5sum $file_to_create)
    if [[ "$verbose" = "true" ]]; then
        echo "$str ${md5hash})"
    fi

    md5file="$BM_REPOSITORY_ROOT/${BM_ARCHIVE_PREFIX}-${TODAY}.md5"

    # Check if the md5file contains already the md5sum of the file_to_create.
    # In this case, the new md5sum overwrites the old one.
    if grep "$base" $md5file >/dev/null 2>&1 ; then
        previous_md5sum=$(get_md5sum_from_file $base $md5file)
        sed -e "/$base/s/$previous_md5sum/$md5hash/" -i $md5file
    else
        echo "$md5hash  $base" >> $md5file
    fi

    # Now that the file is created, remove previous duplicates if exists...
    purge_duplicate_archives $file_to_create ||
        error "Unable to purge duplicates of \$file_to_create"

    # ownership
    chown_archive "$file_to_create"
}

# security fixes if BM_REPOSITORY_SECURE is set to true
function chown_archive {
    file="$1"
    if [[ "$BM_REPOSITORY_SECURE" = "true" ]]; then
        chown $BM_REPOSITORY_USER:$BM_REPOSITORY_GROUP $file ||
            warning "Unable to change the owner of \"\$file\"."
        chmod $BM_ARCHIVE_CHMOD $file ||
            warning "Unable to change file permissions of \"\$file\"."
    fi
}

# this is the callback wich is run when backup-manager
# is stopped with a signal like SIGTERM or SIGKILL
# We have to take care of the incomplete builds, in order to leave a repository with
# only trustable archives and friends.
function clean_exit()
{
    echo ""
    warning "Warning, process interrupted."
    if [[ -n "$bm_pending_archive" ]] && [[ -e "$bm_pending_archive" ]]; then

        # remove the archive that is being built (it's incomplete)
        warning "Removing archive \"\$bm_pending_archive\" (build interrupted)."
        rm -f $bm_pending_archive

        # if we're building incremental stuff, restore the original incremental list file
        if [[ -n "$bm_pending_incremental_list" ]]; then
            if [[ -e "${bm_pending_incremental_list}.orig" ]]; then
                warning "Restoring incremental-building details list: \"\$bm_pending_incremental_list\"."
                rm -f $bm_pending_incremental_list
                mv "${bm_pending_incremental_list}.orig" $bm_pending_incremental_list
            else
                warning "Removing incremental-building details list: \"$bm_pending_incremental_list\"."
                rm -f $bm_pending_incremental_list
            fi
        fi
    fi
    release_lock
    bm_dbus_send_progress 100 "Finished"
    bm_dbus_send_event "shutdown" "70"
    exit 70
}

function commit_archives()
{
    file_to_create="$1"
    debug "commit_archives ($file_to_create)"

    if [[ "$BM_TARBALL_FILETYPE" = "dar" ]]; then
        for dar_file in $file_to_create.*.dar
        do
            commit_archive "$dar_file"
        done
    else
        commit_archive "$file_to_create"
    fi
}

function handle_tarball_error()
{
    target="$1"
    logfile="$2"
    debug "handle_tarball_error ($target, $logfile)"

    warning "Unable to create \"\$target\", check \$logfile"
    nb_err=$(($nb_err + 1))

    chown_archive "$target"
}

function __exec_meta_command()
{
    nice="$nice_bin -n $BM_ARCHIVE_NICE_LEVEL"
    command="$nice $1"
    file_to_create="$2"
    compress="$3"
    debug "__exec_meta_command ($command, $file_to_create, $compress)"

    if [[ -f $file_to_create ]] && [[ $force != true ]]

    then
        warning "File \$file_to_create already exists, skipping."
        export BM_RET=""
    else
        logfile=$(mktemp ${BM_TEMP_DIR}/bm-command.XXXXXX)

        case "$compress" in
        "gzip"|"gz"|"bzip"|"bzip2")
            if [[ "$compress" = "gzip" ]] ||
               [[ "$compress" = "gz" ]]; then
               compress_bin=$gzip
                if [[ -z "$compress_bin" ]]; then
                    error "gzip is not installed but gzip compression needed."
                fi
               ext="gz"
            fi
            if [[ "$compress" = "bzip2" ]] ||
               [[ "$compress" = "bzip" ]]; then
               compress_bin=$bzip
                if [[ -z "$compress_bin" ]]; then
                    error "bzip2 is not installed but bzip2 compression needed."
                fi
               ext="bz2"
            fi

            if [[ -n "$compress_bin" ]] && [[ -x "$compress_bin" ]]; then
                debug "$command > $file_to_create 2> $logfile"
                tail_logfile "$logfile"
                if [[ "$BM_ENCRYPTION_METHOD" = "gpg" ]]; then
                    $command 2>$logfile | $nice $compress_bin -f -q -9 2>$logfile | $nice $gpg $BM__GPG_HOMEDIR -r "$BM_ENCRYPTION_RECIPIENT" -e > $file_to_create.$ext.gpg 2> $logfile
                    debug "$command | $nice $compress_bin -f -q -9 | $nice $gpg $BM__GPG_HOMEDIR -r \"$BM_ENCRYPTION_RECIPIENT\" -e > $file_to_create.$ext.gpg 2> $logfile"
                    file_to_create="$file_to_create.$ext.gpg"
                else
                    $command 2> $logfile | $nice $compress_bin -f -q -9 > $file_to_create.$ext 2> $logfile
                    file_to_create="$file_to_create.$ext"
                fi

                if [[ $? -gt 0 ]]; then
                    warning "Unable to exec \$command; check \$logfile"
                    rm -f $file_to_create
                else
                    rm -f $logfile
                fi
            else
                error "Compressor \$compress is needed."
            fi
        ;;
        ""|"uncompressed"|"none")
            if [[ "$verbosedebug" == "true" ]]; then
                tail -f $logfile &
            fi

            debug "$command 1> $file_to_create 2>$logfile"
            tail_logfile "$logfile"
            if [[ "$BM_ENCRYPTION_METHOD" = "gpg" ]]; then
                $command | $nice $gpg $BM__GPG_HOMEDIR -r "$BM_ENCRYPTION_RECIPIENT" -e > $file_to_create.gpg 2> $logfile
                file_to_create="$file_to_create.gpg"
            else
                $command 1> $file_to_create 2>$logfile
            fi

            if [[ $? -gt 0 ]]; then
                warning "Unable to exec \$command; check \$logfile"
                rm -f $file_to_create
            else
                rm -f $logfile
            fi
        ;;
        *)
            error "No such compressor supported: \$compress."
        ;;
        esac

        # make sure we didn't loose the archive
        if [[ ! -e $file_to_create ]]; then
            error "Unable to find \$file_to_create"
        fi
        export BM_RET="$file_to_create"
    fi
}

function __create_file_with_meta_command()
{
    debug "__create_file_with_meta_command ()"

    __exec_meta_command "$command" "$file_to_create" "$compress"
    file_to_create="$BM_RET"
    if [[ -n "$BM_RET" ]]; then
        commit_archive "$file_to_create"
    fi
    chown_archive "$file_to_create"
}


# Thanks to Michel Grentzinger for his
# smart ideas/remarks about that function.
function __get_flags_relative_blacklist()
{
    switch="$1"
    target="$2"
    debug "__get_flags_relative_blacklist ($switch, $target)"

    if [ "$target" != "/" ]; then
        target=${target%/}
    fi
    blacklist=""
    for pattern in $BM_TARBALL_BLACKLIST
    do
        # absolute paths
        char=$(expr substr $pattern 1 1)
        if [[ "$char" = "/" ]]; then

           # we blacklist only absolute paths related to $target
           if [[ "${pattern#$target}" != "$pattern" ]]; then

                # making a relative path...
                pattern="${pattern#$target}"
                length=$(expr length $pattern)
                # for $target="/", no spare / is left at the beggining
                # after the # substitution; thus take substr from pos 1
                if [ "$target" != "/" ]; then
                    pattern=$(expr substr $pattern 2 $length)
                else
                    pattern=$(expr substr $pattern 1 $length)
                fi

                # ...and blacklisting it
                blacklist="$blacklist ${switch}${pattern}"
           fi

        # relative path are blindly appended to the blacklist
        else
            blacklist="$blacklist ${switch}${pattern}"
        fi
    done

}

function __get_flags_dar_blacklist()
{
    target="$1"
    debug "__get_flags_dar_blacklist ($target)"

    __get_flags_relative_blacklist "-P" "$target"
}

function __get_flags_tar_blacklist()
{
    target="$1"
    debug "__get_flags_tar_blacklist ($target)"

    __get_flags_relative_blacklist "--exclude=" "$target"
}


function __get_flags_zip_dump_symlinks()
{
    debug "__get_flags_zip_dump_symlinks"

    export ZIP=""
    export ZIPOPT=""
    y="-y"
    if [[ "$BM_TARBALL_DUMPSYMLINKS" = "true" ]]; then
        y=""
    fi
    echo "$y"
}

function __get_flags_tar_dump_symlinks()
{
    debug "__get_flags_tar_dump_symlinks"

    h=""
    if [[ "$BM_TARBALL_DUMPSYMLINKS" = "true" ]]; then
        h="-h "
    fi
    echo "$h"
}

function __get_file_to_create()
{
    target="$1"
    debug "__get_file_to_create ($target)"

    dir_name=$(get_dir_name "$target" $BM_TARBALL_NAMEFORMAT)
    file_to_create="$BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX$dir_name.$TODAY${master}.$BM_TARBALL_FILETYPE"

    # dar appends itself the ".dar" extension
    if [[ "$BM_TARBALL_FILETYPE" = "dar" ]]; then
        file_to_create="$BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX$dir_name.$TODAY${master}"
    fi
    echo "$file_to_create"
}

function __get_file_to_create_remote()
{
    target="$1"
    host="$2"
    debug "__get_file_to_create_remote ($target, $host)"

    dir_name=$(get_dir_name "$target" $BM_TARBALL_NAMEFORMAT)
    file_to_create="$BM_REPOSITORY_ROOT/${host}${dir_name}.$TODAY${master}.$BM_TARBALL_FILETYPE"

    echo "$file_to_create"
}

function __get_master_day()
{
    debug "__get_master_day ()"

    if [[ -z "$BM_TARBALLINC_MASTERDATETYPE" ]]; then
        error "No frequency given, set BM_TARBALLINC_MASTERDATETYPE."
    fi

    case $BM_TARBALLINC_MASTERDATETYPE in
    weekly)
        master_day=$(date +'%w')
    ;;
    monthly)
        master_day=$(date +'%-d')
    ;;
    *)
        error "Unknown frequency: \$BM_TARBALLINC_MASTERDATETYPE"
    ;;
    esac
}

function __init_masterdatevalue()
{
    debug "__init_masterdatevalue ()"

    if [[ -z "$BM_TARBALLINC_MASTERDATEVALUE" ]]; then
        BM_TARBALLINC_MASTERDATEVALUE="1"
    fi
}

function __get_flags_tar_incremental()
{
    dir_name="$1"
    debug "__get_flags_tar_incremental ($dir_name)"

    incremental_list="$BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX$dir_name.incremental.bin"
    bm_pending_incremental_list="$incremental_list"
    if [[ -e "${incremental_list}" ]]; then
        debug "cp $incremental_list ${incremental_list}.orig"
        cp $incremental_list "${incremental_list}.orig"
    fi

    incremental=""
    __get_master_day
    __init_masterdatevalue

    # if master day, we have to purge the incremental list if exists
    # so we'll generate a new one (and then, a full backup).
    if [[ "$master_day" -eq "$BM_TARBALLINC_MASTERDATEVALUE" ]];  then
        info "Building master backup for target: \"\$dir_name\"."
        rm -f "$incremental_list"
    fi
    if [[ -e "$incremental_list" ]]; then
        master=""
    fi
    incremental="--listed-incremental $incremental_list"
}

# This will set the appropriate dar options for making incremental backups.
function __get_flags_dar_incremental()
{
    dir_name="$1"
    debug "__get_flags_dar_incremental ($dir_name)"

    incremental=""

    __get_master_day
    __init_masterdatevalue

    # looking for the youngest last DAR backup available
    for pastdays in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30
    do
        lastday=$(date +'%Y%m%d' --date "$pastdays days ago")
        lastday_dar="$BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX$dir_name.$lastday.dar"
        lastday_dar_first_slice="$BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX$dir_name.$lastday.1.dar"
        lastday_dar_master="$BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX$dir_name.$lastday.master.dar"
        lastday_dar_master_first_slice="$BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX$dir_name.$lastday.master.1.dar"

        if [[ -e $lastday_dar ]] || [[ -e $lastday_dar_first_slice ]] || [[ -e $lastday_dar_master ]]  || [[ -e $lastday_dar_master_first_slice ]]; then
            # we have found a previous dar backup, this one will be used as a reference
            # if needed.
            break
        fi
    done

    # If we aren't the "full backup" day, we take the previous backup as
    # a reference for the incremental stuff.
    # We have to find the previous backup for that...
    if [[ "$master_day" != "$BM_TARBALLINC_MASTERDATEVALUE" ]] ; then

        # Either we have a master backup made lastday...
        if [[ -e $lastday_dar_master ]] ||
           [[ -e $lastday_dar_master_first_slice ]] ; then
            incremental="--ref $BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX$dir_name.$lastday.master"

        # ... Or we have an incremental backup made lastday
        elif [[ -e $lastday_dar ]] || [[ -e $lastday_dar_first_slice ]] ; then
            incremental="--ref $BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX$dir_name.$lastday"
        fi

        # if we use some --ref then, it's not a master but an incremental backup.
        if [[ -n "$incremental" ]] ; then
            master=""
        fi
    fi
}

function __get_flags_dar_maxsize()
{
    debug "__get_flags_dar_maxsize ()"

    if [[ -n "$BM_TARBALL_SLICESIZE" ]]; then
        maxsize="--alter=SI -s $BM_TARBALL_SLICESIZE"
    fi
    echo "$maxsize"
}

function __get_flags_dar_overwrite()
{
    debug "__get_flags_dar_overwrite"

    if [[ $force = true ]] ; then
        overwrite="-w"
    fi

    echo "$overwrite"
}

# FIXME : incremental is not possible remotely
# in the current shape...
function __get_backup_tarball_remote_command()
{
    debug "__get_backup_tarball_remote_command ()"

    oldgzip="$GZIP"
    export GZIP="-n"
    case $BM_TARBALL_FILETYPE in
        tar)
            __get_flags_tar_blacklist "$target"
            command="$tar $blacklist $dumpsymlinks $BM_TARBALL_EXTRA_OPTIONS -p -c "$target""
        ;;
        tar.gz)
            __get_flags_tar_blacklist "$target"
            command="$tar $blacklist $dumpsymlinks $BM_TARBALL_EXTRA_OPTIONS -p -c -z "$target""
        ;;
        tar.bz2|tar.bz)
            __get_flags_tar_blacklist "$target"
            command="$tar $blacklist $dumpsymlinks $BM_TARBALL_EXTRA_OPTIONS -p -c -j "$target""
        ;;
        tar.lz)
            __get_flags_tar_blacklist "$target"
            command="$tar $blacklist $dumpsymlinks $BM_TARBALL_EXTRA_OPTIONS -p -c --lzma "$target""
        ;;
        *)
            error "Remote tarball building is not possible with this archive filetype: \"$BM_TARBALL_FILETYPE\"."
        ;;
    esac
    export GZIP="$oldgzip"
    echo "$nice_bin -n $BM_ARCHIVE_NICE_LEVEL $command"

}

# This function will take care of changing the behaviour of BM
# regarding the error code given
# 0 is a success case (remove the logfile and commit the archive).
# tar/1 is a warning case (file changed; don't remove the logfile but commit the archive).
# dar/11 is a waring case (file changed; don't remove the logfile but commit the archive).
# >1 is an error code (don't remove the logile, don't commit the archive).
function check_error_code()
{
    error_code="$1"
    file_to_create="$2"
    logfile="$3"

    if [[ -z "$error_code" ]]; then
        error_code=0
    fi

    # Error checks can depend on the command/error code returned
    case "$BM__CURRENT_COMMAND" in
        "tar")
            if [[ "$error_code" == "1" ]]; then
                warning "Tar reported a file changed during archive creation."
                commit_archives "$file_to_create"
            elif [[ "$error_code" -gt 0 ]]; then
                handle_tarball_error "$file_to_create" "$logfile"
            else
                rm -f $logfile
                commit_archives "$file_to_create"
            fi
        ;;
        "dar")
            if [[ "$error_code" == "11" ]]; then
                warning "Dar reported a file changed during archive creation."
                commit_archives "$file_to_create"
            elif [[ "$error_code" -gt 0 ]]; then
                handle_tarball_error "$file_to_create" "$logfile"
            else
                rm -f $logfile
                commit_archives "$file_to_create"
            fi
        ;;
        *)
            if [[ "$error_code" -gt 0 ]]; then
                handle_tarball_error "$file_to_create" "$logfile"
            else
                rm -f $logfile
                commit_archives "$file_to_create"
            fi
        ;;
    esac

    # Reset the error code
    error_code=0
}

function __get_backup_tarball_command()
{
    debug "__get_backup_tarball_command ()"

    case $BM_TARBALL_FILETYPE in
        tar)
            __get_flags_tar_blacklist "$target"
            command="$tar $incremental $blacklist $dumpsymlinks $BM_TARBALL_EXTRA_OPTIONS -p -c -f"
        ;;
        tar.gz)
            __get_flags_tar_blacklist "$target"
            command="$tar $incremental $blacklist $dumpsymlinks $BM_TARBALL_EXTRA_OPTIONS -p -c -z -f"
        ;;
        tar.bz2|tar.bz)
            if [[ ! -x $bzip ]]; then
                error "The archive type \"tar.bz2\" depends on the tool \"\$bzip\"."
            fi
            __get_flags_tar_blacklist "$target"
            command="$tar $incremental $blacklist $dumpsymlinks $BM_TARBALL_EXTRA_OPTIONS -p -c -j -f"
        ;;
        tar.lz)
            if [[ ! -x $lzma ]]; then
                error "The archive type \"tar.lz\" depends on the tool \"\$lzma\"."
            fi
            __get_flags_tar_blacklist "$target"
            command="$tar $incremental $blacklist $dumpsymlinks $BM_TARBALL_EXTRA_OPTIONS -p -c --lzma -f"
        ;;
        zip)
            if [[ ! -x $zip ]]; then
                error "The archive type \"zip\" depends on the tool \"\$zip\"."
            fi
            command="$zip $dumpsymlinks $BM_TARBALL_EXTRA_OPTIONS -r"
        ;;
        dar)
            if [[ ! -x $dar ]]; then
                error "The archive type \"dar\" depends on the tool \"\$dar\"."
            fi
            __get_flags_dar_blacklist "$target"
            command="$dar $incremental $blacklist $maxsize $overwrite $BM_TARBALL_EXTRA_OPTIONS -z9 -Q -c $file_to_create -R"
        ;;
        *)
            error "The archive type \"\$BM_TARBALL_FILETYPE\" is not supported."
            return 1
        ;;
    esac
    echo "$nice_bin -n $BM_ARCHIVE_NICE_LEVEL $command"
}

function build_clear_archive
{
    debug "build_clear_archive ()"

    logfile=$(mktemp ${BM_TEMP_DIR}/bm-tarball.log.XXXXXX)
    debug "logfile: $logfile"

    # A couple of archive types have a special command line
    case "$BM_TARBALL_FILETYPE" in

        # dar has a special commandline, that cannot fit the common tar way
        "dar")
            BM__CURRENT_COMMAND="dar"
            debug "$command $target> $logfile 2>&1"
            tail_logfile "$logfile"

            $command "$target"> $logfile 2>&1 || error_code=$?
            check_error_code "$error_code" "$file_to_create" "$logfile"
        ;;

        # the common commandline
        *)
            # tar, tar.gz, tar.bz2, tar.whatever
            if [[ "${BM_TARBALL_FILETYPE:0:3}" == "tar" ]] ; then
                BM__CURRENT_COMMAND="tar"
            else
                BM__CURRENT_COMMAND="generic"
            fi
            debug "$command $file_to_create \"$target\" > $logfile 2>&1"
            tail_logfile "$logfile"
            debug "$command $file_to_create \"$target\""
            $command $file_to_create "$target" > $logfile 2>&1 || error_code=$?
            check_error_code "$error_code" "$file_to_create" "$logfile"
        ;;
    esac
    BM__CURRENT_COMMAND=""
}


function build_encrypted_archive
{
    debug "build_encrypted_archive"
    logfile=$(mktemp ${BM_TEMP_DIR}/bm-tarball.log.XXXXXX)
    debug "logfile: $logfile"

    if [[ -z "$BM_ENCRYPTION_RECIPIENT" ]]; then
        error "The configuration variable \"BM_ENCRYPTION_RECIPIENT\" must be defined."
    fi

    if [[ "$BM_TARBALL_FILETYPE" = "tar.lz" ]] ||
       [[ "$BM_TARBALL_FILETYPE" = "zip" ]] ||
       [[ "$BM_TARBALL_FILETYPE" = "dar" ]]; then
        error "The encryption is not yet possible with \"\$BM_TARBALL_FILETYPE\" archives."
    fi

    file_to_create="$file_to_create.gpg"

    debug "$command - \"$target\" 2>>$logfile | $gpg $BM__GPG_HOMEDIR -r \"$BM_ENCRYPTION_RECIPIENT\" -e > $file_to_create 2>> $logfile"
    tail_logfile "$logfile"

    $command - "$target" 2>>$logfile | $gpg $BM__GPG_HOMEDIR -r "$BM_ENCRYPTION_RECIPIENT" -e > $file_to_create 2>> $logfile || error_code=$?
    check_error_code "$error_code" "$file_to_create" "$logfile"
}

function __build_local_archive()
{
    target="$1"
    dir_name="$2"
    debug "__build_local_archive ($target, $dir_name)"

    file_to_create=$(__get_file_to_create "$target")
    command="$(__get_backup_tarball_command)" ||
        error "The archive type \"\$BM_TARBALL_FILETYPE\" is not supported."

    # dar is not like tar, we have to manually check for existing .1.dar files
    if [[ $BM_TARBALL_FILETYPE = dar ]]; then
        file_to_check="$BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX$dir_name.$TODAY.1.dar"
    else
        file_to_check="$file_to_create"
    fi

    if [[ "$BM_ENCRYPTION_METHOD" = "gpg" ]]; then
        file_to_check="$file_to_check.gpg"
    fi


    # let's exec the command
    if [[ ! -e "$file_to_check" ]] || [[ "$force" = "true" ]]; then
        if [[ "$BM_ENCRYPTION_METHOD" = "gpg" ]]; then
            if [[ ! -x $gpg ]]; then
                error "The program \"\$gpg\" is needed."
            fi
            bm_pending_archive="${file_to_check}"
            build_encrypted_archive
        else
            bm_pending_archive="${file_to_check}"
            build_clear_archive
        fi
    else
        warning "File \$file_to_check already exists, skipping."
        debug "rm -f ${bm_pending_incremental_list}.orig"
        rm -f "${bm_pending_incremental_list}.orig"
        continue
    fi
}

function __build_remote_archive()
{
    target="$1"
    dir_name="$2"
    debug "__build_remote_archive ($target, $dir_name)"

    for host in $BM_UPLOAD_SSH_HOSTS
    do
        logfile=$(mktemp ${BM_TEMP_DIR}/bm-tarball.log.XXXXXX)
        file_to_create=$(__get_file_to_create_remote "$target" "$host")

        command=$(__get_backup_tarball_remote_command) ||
            error "The archive type \"\$BM_TARBALL_FILETYPE\" is not supported."

        remote_command="ssh -p ${BM_UPLOAD_SSH_PORT} -i ${BM_UPLOAD_SSH_KEY} -o BatchMode=yes ${BM_UPLOAD_SSH_USER}@${host} $command"
        file_to_check="$file_to_create"

        if [[ ! -e "$file_to_check" ]] || [[ $force = true ]]; then

            logfile=$(mktemp ${BM_TEMP_DIR}/bm-tarball.log.XXXXXX)

            debug "$remote_command > $file_to_create 2>$logfile"
            tail_logfile "$logfile"
            $remote_command > "$file_to_create" 2>$logfile || error_code=$?
            check_error_code "$error_code" "$file_to_create" "$logfile"
        else
            warning "File \$file_to_check already exists, skipping."
            continue
        fi
    done
}

function __make_remote_tarball_token
{
    t="$1"
    debug "__make_remote_tarball_token ($t)"

    dir_name=$(get_dir_name "$t" $BM_TARBALL_NAMEFORMAT)
    master=".master"
    __build_remote_archive "$t" "$dir_name"
}

function __make_local_tarball_token
{
    t="$1"
    debug "__make_local_tarball_token ($t)"

    # look for the target in the blacklist...
    is_blacklisted="0"
    for blacklist_pattern in $BM_TARBALL_BLACKLIST; do
        if [[ "$t" == "$blacklist_pattern" ]]; then
            is_blacklisted="1"
        fi
    done


    # ignore the target if it's blacklisted
    if [[ "$is_blacklisted" == "1" ]]; then
        info "Target \"\$t\" is found in blacklist, skipping."

    # be sure the target exists
    elif [[ ! -e "$t" ]] || [[ ! -r "$t" ]]; then
        warning "Target \"\$t\" does not exist, skipping."
        nb_err=$(($nb_err + 1))

    # Everything's OK, do the job
    else
        # we assume we'll build a master backup (full archive).
        # If we make incremental backup, the $master keyword
        # will be reset.
        dir_name=$(get_dir_name "$t" $BM_TARBALL_NAMEFORMAT)
        master=".master"

        # handling of incremental options
        incremental=""

        if [[ $method = tarball-incremental ]]
        then
            case "$BM_TARBALL_FILETYPE" in
            "dar")
                __get_flags_dar_incremental "$dir_name"
            ;;
            "tar"|"tar.gz"|"tar.bz2")
                __get_flags_tar_incremental "$dir_name"
            ;;
            esac
        fi
        __build_local_archive "$t" "$dir_name"
    fi
}

function __make_remote_tarball_archives()
{
    debug "__make_remote_tarball_archives"

    nb_err=0
    for target in "${BM_TARBALL_TARGETS[@]}"
    do
        if [[ -z "$target" ]]; then
            continue
        fi
        __make_remote_tarball_token "$target"
    done
}

function __make_local_tarball_archives()
{
    debug "__make_local_tarball_archives"

    nb_err=0
    for target in "${BM_TARBALL_TARGETS[@]}"
    do
        if [[ -z "$target" ]]; then
            continue
        fi
        target_expanded="$(eval 'echo $target')"

        # if the target exists, handle it as a single token
        if [[ -r "$target_expanded" ]]; then
            __make_local_tarball_token "$target_expanded"

        # else try to expand the target in several tokens
        else
            for t in $target_expanded
            do
                __make_local_tarball_token "$t"
            done
        fi
    done
}

# This manages both "tarball" and "tarball-incremental" methods.
# configuration keys: BM_TARBALL_* and BM_TARBALLINC_*
function backup_method_tarball()
{
    method="$1"
    debug "backup_method_tarball ($method)"

    info "Using method \"\$method\"."

    # build the command line
    case $BM_TARBALL_FILETYPE in
    tar|tar.bz2|tar.gz)
        dumpsymlinks="$(__get_flags_tar_dump_symlinks)"
    ;;
    zip)
        dumpsymlinks="$(__get_flags_zip_dump_symlinks)"
    ;;
    dar)
        maxsize="$(__get_flags_dar_maxsize)"
        overwrite="$(__get_flags_dar_overwrite)"
    ;;
    esac

    if [[ "$BM_TARBALL_OVER_SSH" != "true" ]]; then
        __make_local_tarball_archives
    else
        __make_remote_tarball_archives
    fi

    # Handle errors
    # since version 0.8, BM's follows up its process even if errors were triggered
    # during the archive generation.
    if [[ $nb_err -eq 1 ]]; then
        warning "1 error occurred during the tarball generation."
    elif [[ $nb_err -gt 1 ]]; then
        warning "\$nb_err errors occurred during the tarball generation."
    fi
}

function backup_method_pgsql()
{
    method="$1"
    pgsql_conffile="$HOME/.pgpass"
    pgsql_conffile_bm="$HOME/.pgpass.backup-manager.bak"

    debug "backup_method_pgsql ($method)"

    info "Using method \"\$method\"."
    if [[ -x $pgdump ]] && [[ -x ${pgdump}all ]]; then
        :
    else
        error "The \"postgresql\" method is chosen, but \$pgdump and/or \$pgdumpall are not found."
    fi

    # Allow empty host when connecting to postgress with unix sockets.

    if [[ "X$BM_PGSQL_HOST" = "X" ]]; then
        BM_PGSQL_HOSTFLAGS=""
    else
        BM_PGSQL_HOSTFLAGS="-h$BM_PGSQL_HOST"
    fi
    opt=" -U$BM_PGSQL_ADMINLOGIN $BM_PGSQL_HOSTFLAGS -p$BM_PGSQL_PORT"

    # We need a second variable, to know if the backup pgpass file was used.

    BM_SHOULD_PURGE_PGPASS="false"
    BM_USING_BACKUP_PGPASS="false"

    if [[ -f $pgsql_conffile ]]; then
        info "Found existing PgSQL client configuration file: \$pgsql_conffile"
        info "Looking for matching credentials in this file..."
        if ! grep -qE "(${BM_PGSQL_HOST}|[^:]*):(${BM_PGSQL_PORT}|[^:]*):[^:]*:${BM_PGSQL_ADMINLOGIN}:${BM_PGSQL_ADMINPASS}" $pgsql_conffile; then
            info "No matching credentials: inserting our own."
            BM_SHOULD_PURGE_PGPASS="true"
            BM_USING_BACKUP_PGPASS="true"
            mv $pgsql_conffile $pgsql_conffile_bm
            touch $pgsql_conffile
            chmod 0600 $pgsql_conffile
            echo "${BM_PGSQL_HOST}:${BM_PGSQL_PORT}:*:${BM_PGSQL_ADMINLOGIN}:${BM_PGSQL_ADMINPASS}" >> $pgsql_conffile
        fi
    else
        warning "Creating a default PgSQL client configuration file: \$HOME/.pgpass"
        touch $pgsql_conffile
        chmod 0600 $pgsql_conffile
        echo "${BM_PGSQL_HOST}:${BM_PGSQL_PORT}:*:${BM_PGSQL_ADMINLOGIN}:${BM_PGSQL_ADMINPASS}" >> $pgsql_conffile
    fi

    compress="$BM_PGSQL_FILETYPE"

    for database in $BM_PGSQL_DATABASES
    do
        if [[ "$database" = "__ALL__" ]]; then
            file_to_create="$BM_REPOSITORY_ROOT/${BM_ARCHIVE_PREFIX}-all-pgsql-databases.$TODAY.sql"
            command="${pgdump}all $opt $BM_PGSQL_EXTRA_OPTIONS"
        else
            file_to_create="$BM_REPOSITORY_ROOT/${BM_ARCHIVE_PREFIX}-pgsql-${database}.$TODAY.sql"
            command="$pgdump $opt $database $BM_PGSQL_EXTRA_OPTIONS"
        fi
        __create_file_with_meta_command
    done

    # purge the .pgpass file, if created by Backup Manager
    if [[ "$BM_SHOULD_PURGE_PGPASS" == "true" ]]; then
        info "Removing default PostgreSQL password file: \$pgsql_conffile"
	rm -f $pgsql_conffile
        if [[ "$BM_USING_BACKUP_PGPASS" == "true" ]]; then
            info "restoring initial \$pgsql_conffile file from backup."
            warning "To avoid problems with \$pgsql_conffile, insert the configured host:port:database:user:password inside."
            mv $pgsql_conffile_bm $pgsql_conffile
        fi
    fi
}


function backup_method_mysql()
{
    method="$1"
    mysql_conffile="$HOME/.backup-manager_my.cnf"

    debug "backup_method_mysql ($method)"

    info "Using method \"\$method\"."
    if [[ ! -x $mysqldump ]]; then
        error "The \"mysql\" method is chosen, but \$mysqldump is not found."
    fi

    opt=""
    if [[ "$BM_MYSQL_SAFEDUMPS" = "true" ]]; then
        opt="--opt"
    fi

    # if a MySQL Client conffile exists, the password must be inside
    if [[ -f $mysql_conffile ]]; then
        info "Using existing MySQL client configuration file: \$mysql_conffile"
        BM_SHOULD_PURGE_MYCNF="false"
    # we create a default one, just with the password
    else
        warning "Creating a default MySQL client configuration file: \$mysql_conffile"
        echo "[client]" > $mysql_conffile
        echo "# The following password will be sent to all standard MySQL clients" >> $mysql_conffile
        chmod 600 $mysql_conffile
        echo "password=\"$BM_MYSQL_ADMINPASS\"" >> $mysql_conffile
        BM_SHOULD_PURGE_MYCNF="true"
    fi
    base_command="$mysqldump --defaults-extra-file=$mysql_conffile $opt -u$BM_MYSQL_ADMINLOGIN -h$BM_MYSQL_HOST -P$BM_MYSQL_PORT $BM_MYSQL_EXTRA_OPTIONS"
    compress="$BM_MYSQL_FILETYPE"

    for database in $BM_MYSQL_DATABASES
    do
        if [[ "$database" = "__ALL__" ]]; then
            file_to_create="$BM_REPOSITORY_ROOT/${BM_ARCHIVE_PREFIX}-all-mysql-databases.$TODAY.sql"
            command="$base_command --all-databases"
        else
            file_to_create="$BM_REPOSITORY_ROOT/${BM_ARCHIVE_PREFIX}-mysql-${database}.$TODAY.sql"
            command="$base_command $database"
        fi
        __create_file_with_meta_command
    done

    # purge the my.cnf file, if created by Backup Manager
    if [[ "$BM_SHOULD_PURGE_MYCNF" == "true" ]]; then
        info "Removing default MySQL client configuration file: \$mysql_conffile"
        rm -f $mysql_conffile
    fi
}

function backup_method_svn()
{
    method="$1"
    debug "backup_method_svn ($method)"

    info "Using method \"\$method\"."
    if [[ ! -x $svnadmin ]]; then
        error "The \"svn\" method is chosen, but \$svnadmin is not found."
    fi

    for repository in $BM_SVN_REPOSITORIES
    do
        if [[ ! -d $repository ]]; then
            warning "SVN repository \"\$repository\" is not valid; skipping."
        else
            archive_name=$(get_dir_name $repository "long")
            file_to_create="$BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX$archive_name.$TODAY.svn"
            command="$svnadmin -q dump $repository"
            compress="$BM_SVN_COMPRESSWITH"
            __create_file_with_meta_command
        fi
    done
}

function backup_method_pipe()
{
    method="$1"
    debug "backup_method_pipe ($method)"

    info "Using method \"\$method\"."
    index=0

    # parse each BM_PIPE_NAME's
    for archive in ${BM_PIPE_NAME[*]}
    do
        # make sure everything is here for this archive
        if [[ -z "${BM_PIPE_COMMAND[$index]}" ]] ||
           [[ -z "${BM_PIPE_FILETYPE[$index]}" ]]; then
                warning "Not enough args for this archive (\$archive), skipping."
                continue
        fi
        command="${BM_PIPE_COMMAND[$index]}"
        filetype="${BM_PIPE_FILETYPE[$index]}"
        file_to_create="$BM_REPOSITORY_ROOT/$BM_ARCHIVE_PREFIX-$archive.$TODAY.$filetype"
        compress="${BM_PIPE_COMPRESS[$index]}"
        __create_file_with_meta_command || error "Cannot create archive."

        # update the index mark
        index=$(($index + 1))
    done
}
