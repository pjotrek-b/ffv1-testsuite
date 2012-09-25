#!/bin/bash
# @date: 20.Sep.2012
# @author: Peter Bubestinger
# @description:
#   This script is used to compare checksums created during the FFv1-testsuite 
#   and outputs the results in a reasonable format.

# @history:
#   20.Sep.2012     peter_b     - Started.
#                               - Added diff-handling + result textfile.

source "test_ffv1.sh" "include"         # Get some common code.

# Overload variables from "test_ffv1" script here:
DEBUG=0                                 # Toggle debug on/off

# Diff for ffmpeg frame checksum format:
#   *) Ignore whitespaces (-w)
#   *) Display differences side by side (-y)
#   *) Increase output length per line to 168 characters (-W 168)
#   *) Don't show common lines (--suppress-common-lines)

DIFF="/usr/bin/diff"
DIFF_ARGS="--suppress-common-lines -W 168 -wy"


function compare_frame_checksums
{
    local DIR_IN="$1"
    local DIR_CHECK_BASE="$2"
    local CHECK_METHOD="$3"

    local RESULT_FILE="$DIR_OUT_RESULTS/results-$CHECK_METHOD.txt"

    # Iterate through all frame checksum files of source videos:
    for FRAMECHECK_REF in `ls $DIR_IN/*.$CHECK_METHOD`; do
        local INPUT_FILE=$(basename "$FRAMECHECK_REF")
        local VIDEO_NAME="$(basename ${INPUT_FILE%%.*})"

        local DIR_CHECK="$DIR_CHECK_BASE/$VIDEO_NAME"
        local CHECK_MASK="$DIR_CHECK/*.$CHECK_METHOD"
        
        local RESULT_SUM=0
        local FILE_COUNT=0
        local FILE_COUNT_BAD=0
        local MISMATCH_FILE="$DIR_IN/$VIDEO_NAME-mismatch_$CHECK_METHOD.txt"

        log_header "Video: '$VIDEO_NAME'"
        log "
        Reference file: '$FRAMECHECK_REF'
        Files to check in: '$DIR_CHECK'
        Results written to: '$RESULT_FILE'
        "
        log_timestamp "Started '$VIDEO_NAME'"

        # For each source video, iterate through all frame checksums of generated files:
        for FRAMECHECK_FILE in `ls $CHECK_MASK`; do
            log "Checking: '$(basename $FRAMECHECK_FILE)'...   "

            printf "========\n$FRAMECHECK_FILE\n--------\n" >> $MISMATCH_FILE       # Log filename.
            $DIFF $DIFF_ARGS "$FRAMECHECK_REF" "$FRAMECHECK_FILE" >> $MISMATCH_FILE
            RESULT=$?

            if [ $RESULT -ne 0 ]; then
                RESULT_SUM=$(($RESULT_SUM + 1))
                FILE_COUNT_BAD=$(($FILE_COUNT_BAD + 1))
                echo "" >> $MISMATCH_FILE
            fi
            log "($RESULT)\n"
            FILE_COUNT=$(($FILE_COUNT + 1)) # Count how many files were checked.
        done

        echo "'$VIDEO_NAME': $FILE_COUNT files checked" >> $RESULT_FILE

        # If no mismatches occured, delete the mismatch-file:
        if [ $RESULT_SUM -eq 0 ]; then
            log "All results good. Clearing mismatch log for '$VIDEO_NAME'.\n"
            rm "$MISMATCH_FILE"
        else
            echo "'$VIDEO_NAME': $FILE_COUNT_BAD files with errors!" >> $RESULT_FILE
        fi

        log_timestamp "Finished '$VIDEO_NAME' ($FILE_COUNT files checked)"
        pause 0
        echo ""
    done
}


function initialize2
{
    local DIR_OUT="$1"
    local LABEL="$2"

    # Call "parent" initialize function to get all foldernames:
    initialize "$DIR_OUT" "$LABEL"

    DIR_OUT_RESULTS="$DIR_OUT/results"
    make_dir "$DIR_OUT_RESULTS"
}


# -----------------------------------------------
case "$1" in
    framemd5)
        FRAMECHECK_METHOD="$1"
        DIR_OUT="$2"

        initialize2 "$DIR_OUT" "FFv1 Testsuite - Result evaluation"
        compare_frame_checksums "$DIR_OUT_CHECKSUM" "$DIR_OUT_VIDEO" "$FRAMECHECK_METHOD"
    ;;

    *)
        echo ""
        echo "SYNTAX: $0 (framemd5) <test_output_dir>"
        echo ""
    ;;
esac
