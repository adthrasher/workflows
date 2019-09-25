## Description: 
##
## This WDL tool wraps the MultiQC tool (https://multiqc.info/).
## MultiQC aggregates quality control results for bioinformatics.

task multiqc {
    File star
    File dups
    String validate_sam_string
    Array[File] qualimap_bamqc
    Array[File] qualimap_rnaseq
    Array[File] fastqc_files
    File flagstat_file

    command {
        echo ${star} > file_list.txt
        echo ${dups} >> file_list.txt
        echo ${validate_sam_string} > validate_sam.txt
        echo validate_sam.txt >> file_list.txt
        for file in ${sep=' ' qualimap_bamqc} ; do
            echo $file >> file_list.txt
        done
        for file in ${sep=' ' qualimap_rnaseq} ; do
            echo $file >> file_list.txt
        done
        for file in ${sep=' ' fastqc_files} ; do
            echo $file >> file_list.txt
        done
        echo ${flagstat_file} >> file_list.txt

        multiqc --file-list file_list.txt -o multiqc_results
    }

    runtime {
        docker: 'stjudecloud/bioinformatics-base:bleeding-edge'
    }

    output {
        File out = "multiqc_results"
    }
}