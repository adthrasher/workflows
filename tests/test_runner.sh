function __run_wdl_workflow
{
    local WDL
    local INPUT

    WDL=$1
    INPUT=$2

    miniwdl run -i $INPUT $WDL
}

function __run_wdl_task
{
    local WDL
    local INPUT
    local TASKNAME

    WDL=$1
    INPUT=$2
    TASKNAME=$3

    miniwdl run -i $INPUT --task $TASKNAME $WDL
}