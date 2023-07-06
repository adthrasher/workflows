source ../test_runner.sh

function test_download
{
    __run_wdl_task ../../tools/util.wdl util_download.json download
}


test_download