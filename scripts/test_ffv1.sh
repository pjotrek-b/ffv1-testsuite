#!/bin/bash
# @date: 17. Sep 2012
# @author: Peter Bubestinger
# @description:
#   This should be the final test-suite for automated, reproduceable
#   tests of the FFv1 video codec. It was designed for reliability
#   and performance tests in order to release FFv1.3, but should be
#   suitable for future versions, too.
#
#   The input testvideos are taken from xiph.org's testvideo collection (http://media.xiph.org/video).
#       YUV:
#           - Derf's Collection:
#               http://media.xiph.org/video/derf/
#       RGB:
#           - "Sintel" (Open Movie project by Blender Foundation)
#               http://media.xiph.org/sintel/
#           - SVT test sequences:
#               http://media.xiph.org/svt/
#
#   There is no conversion performed on the input material, except encoding it
#   with FFv1. Colorspace, resolution, etc. are taken as-is.

# Tested use-cases:
#   GOP size
#   Colorspaces & resolutions: only the ones for which input videos exist!
#   Slices
#   Slice-CRC
#   Multipass

# Tests are performed in a nested way, in order to check all kinds of combinations.
# Here is some pseudo-code representing the test-suite:
#    context (golomb,rice) {
#        coders (ac,vlc) {
#            slices (1,4,6,9,12,16,24,30) {
#                slicecrc (0,1) {
#                    gop (1,5,10,25,50,100,200,300) {
#                        firstpass
#                        2nd-pass(this logfile)
#                        2nd-pass(previous logfile)
#
#                        framemd5-checksum(firstpass)
#                        framemd5-checksum(2ndpass)
#                        framemd5-checksum(2ndpass-2)
#                    }
#                }
#            }
#        }
#    }
 
# @history:
#   20.Sep.2012     peter_b     - Added larget GOP sizes (100 200 300).
#                               - Skipping video encoding if frame checksum file exists.
#                               - Added iteration through thread numbers.
#                               - Added overloading test-parameters from external file.
#   18.Sep.2012     peter_b     - Added logging.
#                               - Added execution functions.
#                               - Added result CSV generator.
#                               - Added frame checksum calculation.
#                               - Added iteration loop through test parameters.
#   17.Sep.2012     peter_b     - Started.
#

DEBUG=0                                 # Toggle debug on/off
NO_EXEC=0                               # Toggle execution on/off

TIMESTAMP=$(date +%Y%m%d_%H%M)
LOGFILE_MASK="%s-$TIMESTAMP.log"
STATS_MASK="%s.stats"                   # Multi-pass stats file
FRAMECHECK_METHOD="framemd5"

# --- Directories and files:
DIR_FFMPEG="/home/pb/install/ffmpeg/ffmpeg-git"
FILE_FFV1_PARAMS="ffv1_testparams.txt"

# --- Applications used:
FFMPEG="./ffmpeg"
FFPROBE="./ffprobe"


# --- Parameter values to be used:
FFV1_VERSIONS="3"
FFV1_CONTEXTS="0 1"
FFV1_CODERS="0 1"
FFV1_GOP_SIZES="1 10 25 50 100 200 300"
FFV1_SLICES="4 6 9 12 16 24 30"
FFV1_SLICECRCS="0 1"
FFV1_THREADS="4"



# -----------------------------------------------

function log
{
    local MSG="$1"
    
    if [ -z "$LOGFILE" ]; then
        echo "ERROR: Logfile name empty!"
        return 1
    fi

    printf "$MSG"
    printf "$MSG" >> $LOGFILE
}


function log_timestamp
{
    local MSG="$1"
    local TIMESTAMP=$(date)
    log "$MSG: $TIMESTAMP\n"
}


function log_header
{
    local MSG="$1"
    log "===================================\n$MSG\n===================================\n\n"
}

function log_header2
{
    local MSG="$1"
    log "==============================\n$MSG\n-----------------------------\n\n"
}

function log_error
{
    local MSG="$1"
    log "ERROR: $MSG\n"
}

function pause
{
    local PAUSE="$1"
    echo ""

    if [ $DEBUG -eq 0 ]; then
        echo "Waiting $PAUSE seconds..."
        sleep $1
    else
        read -p "Press any key to continue..."
    fi
}


function execute 
{
    local CMD="$1"
    local FILE_OUT="$2"
    local CONTEXT="$3"          # Group logfiles together in that subfolder

    if [ $NO_EXEC -eq 1 ]; then
        echo "WARNING: Execution disabled due to debug mode!"
        EXEC_RESULT=0   # Simulate successful execution.

        log_header2 "$CMD"
        return 0
    fi

    if [ -n "$FILE_OUT" ]; then
        local LOGFILE=""
        FILENAME=$(basename $FILE_OUT)
        LOGFILE="$DIR_LOG/$CONTEXT/$FILENAME.log"
    fi

    log_header2 "$CMD"
    pause 0

    eval $CMD 2>&1 | tee -a $LOGFILE
    EXEC_RESULT=${PIPESTATUS[0]}
    log "Execution return value: $EXEC_RESULT\n"
    return $EXEC_RESULT
}


function probe_media
{
    local FILE_IN="$1"
    local FILE_OUT="$2"
    local PRINT_FORMAT="xml"

    if [[ ! -e "$FILE_IN" || -z "$FILE_OUT" ]];  then
        return 1
    fi

    $FFPROBE -show_streams -show_format -print_format $PRINT_FORMAT $FILE_IN > $FILE_OUT
    return 0
}


function frame_checksums
{
    #return #DELME. Uncomment this line to disable this function!

    local FILE_IN="$1"
    local FILE_OUT="$2"
    local CHECK_METHOD="$3"

    if [ -z "$CHECK_METHOD" ]; then
        log_error "No check method given!\n"
        return 1
    fi

    if [ ! -s "$FILE_IN" ]; then
        log_error "Input file missing! Cannot generate $CHECK_METHOD for '$FILE_IN'!\n"
        return 2
    fi

    if [ -s "$FILE_OUT" ]; then
        # Don't overwrite already existing files:
        log_header "  Skipping '$CHECK_METHOD' checksums for '$FILE_IN', because they already exist: '$FILE_OUT'\n"
        return 0
    fi
    log_header "  Generating '$CHECK_METHOD' checksums for '$FILE_IN':"

    # Only frames, no audio: "-an"
    cmd="$FFMPEG -i \"$FILE_IN\" -an -f $CHECK_METHOD $FILE_OUT"
    # NEW! Get the audio bytes in order, so their checksum can be compared:
    #cmd="$FFMPEG -i \"$FILE_IN\" -filter_complex "asetnsamples=n=$SET_N_SAMPLES" -f $CHECK_METHOD $FILE_OUT"

    execute "$cmd" "$FILE_OUT"
}


##
# Creates a folder and verifies that it has been created.
# NOTE: This function halts execution if an error occurs.
#   If you just want to create a folder without check,
#   just use plain "mkdir".
function make_dir
{
    local DIR="$1"
    mkdir -p "$DIR"
    if [ ! -d "$DIR" ]; then
        log_error "Could not create directory: '$DIR'!\n"
        exit 1
    fi
    return 0
}


# ----------- FFv1 encoding variants -------------------
function create_ffv1
{
    local VIDEO_IN="$1"
    local VIDEO_OUT="$2"

    if [[ ! -s "$VIDEO_IN" || -z "$VIDEO_OUT" ]]; then
        log_error "Invalid parameters for 'create_ffv1':\n  Input: '$VIDEO_IN'\n  Output: '$VIDEO_OUT'\n\n"
        return 1
    fi

    # Add argument tag values to filename:
    local TAGS=$(printf "%dl_%dcn_%dc_%03dg_%02dt_%02ds_%dcrc" $FFV1_VERSION $FFV1_CONTEXT $FFV1_CODER $FFV1_GOP_SIZE $FFV1_THREAD $FFV1_SLICE $FFV1_SLICECRC)

    log_header "Encoding FFv1 with '$TAGS'"

    local DIR_OUT="$(dirname $VIDEO_OUT)"
    local VIDEO_NAME="$(basename ${VIDEO_IN%.*})"
    local SUFFIX="${VIDEO_OUT##*.}"
    local FILE_OUT="$DIR_OUT/$VIDEO_NAME-$TAGS.$SUFFIX"
    mkdir -p "$DIR_OUT"

    log_timestamp "Encoding started"

    # Skip encoding if frame checksum already exists for these parameters.
    # If you want to re-encode files, delete (or move) their checksum file.
    FRAMECHECK_FILE="$FILE_OUT.$FRAMECHECK_METHOD"
    if [ -s "$FRAMECHECK_FILE" ]; then
        log "Frame checksum for parameters '$TAGS' already exists. Skipping encoding!\n"
        return 0
    fi

    # Construct the actual encoding commandlines (depending on which version of FFv1 to encode):
    if [ "$FFV1_VERSION" -eq 1 ]; then
        CMD="$FFMPEG -i \"$VIDEO_IN\" -an -vcodec ffv1 -level $FFV1_VERSION -context $FFV1_CONTEXT -coder $FFV1_CODER -g $FFV1_GOP_SIZE -threads $FFV1_THREAD \"$FILE_OUT\""
    elif [ "$FFV1_VERSION" -eq 3 ]; then
        CMD="$FFMPEG -i \"$VIDEO_IN\" -an -vcodec ffv1 -level $FFV1_VERSION -context $FFV1_CONTEXT -coder $FFV1_CODER -g $FFV1_GOP_SIZE -threads $FFV1_THREAD -strict experimental -slices $FFV1_SLICE -slicecrc $FFV1_SLICECRC \"$FILE_OUT\""
    else
        log_error "Invalid FFV1 version: $FFV1_VERSION\n"
        return 1
    fi

    LAST_FILE_OUT="$FILE_OUT"
    execute "$CMD" "$FILE_OUT" "$VIDEO_NAME"

    log_timestamp "Encoding finished"
}
# ------------------------------------------------------


function clear_video
{
    local VIDEO_NAME="$1"
    local VIDEO_FILE="$2"

    local FILE_INFO=$(ls -1s "$VIDEO_FILE")

    local RESULT=$(printf "%s;%d;%d;%d;%d;%d;%d;%d" "$FILE_INFO" $FFV1_VERSION $FFV1_CONTEXT $FFV1_CODER $FFV1_GOP_SIZE $FFV1_THREAD $FFV1_SLICE $FFV1_SLICECRC)
    echo $RESULT >> $RESULT_FILE

    rm "$VIDEO_FILE"
}


function run_testsuite
{
    local VIDEOS_IN="$1"
    local DIR_OUT="$2"

    for VIDEO_IN in `ls $VIDEOS_IN`; do
        local INPUT_FILE=$(basename "$VIDEO_IN")
        local INPUT_NAME="$(basename ${INPUT_FILE%.*})"
        local SUFFIX="${INPUT_FILE##*.}"

        local PROBE_FILE="$DIR_OUT_DATA/$INPUT_FILE-ffprobe.xml"
        local FRAMECHECK_FILE="$DIR_OUT_CHECKSUM/$INPUT_FILE.$FRAMECHECK_METHOD"
        local VIDEO_OUT="$DIR_OUT_VIDEO/$INPUT_NAME/$INPUT_NAME.avi"

        # Initialize result file (pseudo CSV):
        RESULT_FILE="$DIR_OUT_DATA/$INPUT_NAME-results.txt"
        echo "Size Filename;Version;Context;Coder;GOP;Threads;Slices;CRC" > $RESULT_FILE

        log_header2 "
        Input video: $VIDEO_IN
        Output video: $VIDEO_OUT
        Probe file: $PROBE_FILE

        FFv1 parameters:
          Versions: $FFV1_VERSIONS
          Contexts: $FFV1_CONTEXTS
          Coders: $FFV1_CODERS
          Slices: $FFV1_SLICES
          Slice CRCs: $FFV1_SLICECRCS
          GOP sizes: $FFV1_GOP_SIZES
          Threads: $FFV1_THREADS
        "
        pause 3

        # Gather information about the original source video:
        probe_media "$VIDEO_IN" "$PROBE_FILE"
        frame_checksums "$VIDEO_IN" "$FRAMECHECK_FILE" "$FRAMECHECK_METHOD"

        # Generate different target versions:
        # (context coders slices slicecrc gop)
        for FFV1_THREAD in $FFV1_THREADS; do
            for FFV1_VERSION in $FFV1_VERSIONS; do
                for FFV1_CONTEXT in $FFV1_CONTEXTS; do
                    for FFV1_CODER in $FFV1_CODERS; do
                        for FFV1_SLICE in $FFV1_SLICES; do
                            for FFV1_SLICECRC in $FFV1_SLICECRCS; do
                                for FFV1_GOP_SIZE in $FFV1_GOP_SIZES; do
                                    create_ffv1 "$VIDEO_IN" "$VIDEO_OUT"
                                    # TODO: multipass!

                                    # "$FRAMECHECK_FILE" is redefined in "create_ffv1":
                                    probe_media "$LAST_FILE_OUT" "$LAST_FILE_OUT-ffprobe.xml"
                                    frame_checksums "$LAST_FILE_OUT" "$FRAMECHECK_FILE" "$FRAMECHECK_METHOD"

                                    clear_video "$INPUT_NAME" "$LAST_FILE_OUT"
                                    pause 0
                                done
                            done
                        done
                    done
                done
            done
        done
        pause 3                 # This is a good exit point for manual execution interruption.
    done
}


function initialize
{
    local DIR_OUT="$1"
    local LABEL="$2"

    DIR_LOG="$DIR_OUT/log"
    DIR_OUT_DATA="$DIR_OUT/data"
    DIR_OUT_VIDEO="$DIR_OUT/video"
    DIR_OUT_CHECKSUM="$DIR_OUT/checksum"

    LOGFILE=$(printf "$DIR_LOG/$LOGFILE_MASK" "$TIMESTAMP")

    # Create output directories:
    make_dir "$DIR_OUT"
    make_dir "$DIR_LOG"
    make_dir "$DIR_OUT_DATA"
    make_dir "$DIR_OUT_VIDEO"
    make_dir "$DIR_OUT_CHECKSUM"

    echo "Logging to '$LOGFILE'"

    log_header "$LABEL"
    log_timestamp "Started"
}


# -----------------------------------------------
case "$1" in
    include)
        # use this to include this file in another script:
        echo "Loading '$0' as library."
    ;;

    ffv1)
        VIDEOS_IN="$2"
        DIR_OUT="$3"

        initialize "$DIR_OUT" "FFv1 Testsuite"

        # Load different test-parameters, if available:
        if [ -s "$FILE_FFV1_PARAMS" ]; then
            log_header2 "Using test parameters from '$FILE_FFV1_PARAMS'."
            source "$FILE_FFV1_PARAMS"
        fi
        run_testsuite "$VIDEOS_IN" "$DIR_OUT"
    ;;

    *)
        echo ""
        echo "SYNTAX: $0 (ffv1) <input_videos> <output_folder>"
        echo ""
        echo "Example:"
        echo "  $0 ffv1 'videos_in/*.y4m' test_results"
        echo ""
    ;;
esac
