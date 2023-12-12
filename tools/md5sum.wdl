## [Homepage](https://github.com/coreutils/coreutils)
#
# SPDX-License-Identifier: MIT
# Copyright St. Jude Children's Research Hospital
version 1.1

# TODO consider consolidating this file with util
#   or renaming to `coreutils.wdl` and moving some of util here

task compute_checksum {
    meta {
        description: "Generates an MD5 checksum for the input file"
        outputs: {
            md5sum: "STDOUT of the `md5sum` command that has been redirected to a file"
        }
    }

    parameter_meta {
        file: "Input file to generate MD5 checksum for"
        modify_disk_size_gb: "Add to or subtract from dynamic disk space allocation. Default disk size is determined by the size of the inputs. Specified in GB."
    }

    input {
        File file
        Int modify_disk_size_gb = 0
    }

    Float file_size = size(file, "GiB")
    Int disk_size_gb = ceil(file_size) + 10 + modify_disk_size_gb

    String outfile_name = basename(file) + ".md5"

    command <<<
        md5sum ~{file} > ~{outfile_name}
    >>>

    output {
        File md5sum = outfile_name
    }

    runtime {
        memory: "4 GB"
        disk: "~{disk_size_gb} GB"
        container: 'docker://ghcr.io/stjudecloud/util:1.3.0'
        maxRetries: 1
    }
}
