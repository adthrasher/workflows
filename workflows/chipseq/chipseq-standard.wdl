## # ChIP-Seq Standard
##
## This WDL workflow runs the BWA ChIP-seq alignment workflow for St. Jude Cloud.
##
## The workflow takes an input BAM file and splits it into fastq files for each read in the pair.
## The read pairs are then passed through BWA alignment to generate a BAM file.
## File validation is performed at several steps, including immediately preceeding output.
##
## ## LICENSING
##
## #### MIT License
##
## Copyright 2021-Present St. Jude Children's Research Hospital
##
## Permission is hereby granted, free of charge, to any person obtaining a copy of this
## software and associated documentation files (the "Software"), to deal in the Software
## without restriction, including without limitation the rights to use, copy, modify, merge,
## publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
## to whom the Software is furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in all copies or
## substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
## BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
## NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
## DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

version 1.0

import "https://raw.githubusercontent.com/stjudecloud/workflows/master/workflows/general/bam-to-fastqs.wdl" as b2fq
import "https://raw.githubusercontent.com/stjude/seaseq/master/workflows/workflows/mapping.wdl" as seaseq_map
import "https://raw.githubusercontent.com/stjude/seaseq/master/workflows/tasks/util.wdl" as seaseq_util
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/ngsderive.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/picard.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/bwa.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/samtools.wdl"
import "https://raw.githubusercontent.com/stjude/seaseq/master/workflows/tasks/samtools.wdl" as seaseq_samtools
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/util.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/deeptools.wdl"

workflow chipseq_standard {
    input {
        File input_bam
        Array[File] bowtie_indexes
        File? excludelist
        String output_prefix = basename(input_bam, ".bam")
        String pairing = "Single-end"
        Int subsample_n_reads = -1
        Int max_retries = 1
        Boolean detect_nproc = false
        Boolean validate_input = true
    }

    parameter_meta {
        input_bam: "Input BAM format file to realign with bwa"
        bwadb_tar_gz: "Database of reference files for the BWA aligner. Can be generated by `chipseq-bwa-db-build.wdl`"
        output_prefix: "Prefix for output files"
        pairing: "Are the sequencing reads paired? [Single-end, Paired-end]"
        subsample_n_reads: "Only process a random sampling of `n` reads. <=`0` for processing entire input BAM."
        max_retries: "Number of times to retry failed steps"
        detect_nproc: "Use all available cores for multi-core steps"
        validate_input: "Run Picard ValidateSamFile on the input BAM"
    }

    call parse_input { input: pairing=pairing }

    if (validate_input) {
       call picard.validate_bam as validate_input_bam { input: bam=input_bam, max_retries=max_retries }
    }

    if (subsample_n_reads > 0) {
        call samtools.subsample {
            input:
                bam=input_bam,
                max_retries=max_retries,
                desired_reads=subsample_n_reads,
                detect_nproc=detect_nproc
        }
    }
    File selected_input_bam = select_first([subsample.sampled_bam, input_bam])

    call util.get_read_groups { input: bam=selected_input_bam, max_retries=max_retries, format_for_star=false }
    Array[String] read_groups = read_lines(get_read_groups.out)

    call b2fq.bam_to_fastqs { input: bam=selected_input_bam, pairing=pairing, max_retries=max_retries, detect_nproc=detect_nproc }

    call samtools.index as samtools_index_input { input: bam=selected_input_bam }

    call ngsderive.read_length { input: bam=selected_input_bam, bai=samtools_index_input.bai }

    if (pairing == "Single-end") {
        scatter (pair in zip(bam_to_fastqs.read1s, read_groups)){
            call seaseq_util.basicfastqstats as basic_stats { input: fastqfile=pair.left }
            call seaseq_map.mapping as bowtie_single_end_mapping { input: fastqfile=pair.left, index_files=bowtie_indexes, metricsfile=basic_stats.metrics_out, blacklist=excludelist, read_length=read_tsv(read_length.read_length_file)[1][3] }
            File chosen_bam = select_first([bowtie_single_end_mapping.bklist_bam, bowtie_single_end_mapping.mkdup_bam, bowtie_single_end_mapping.sorted_bam])
            call util.add_to_bam_header { input: input_bam=chosen_bam, additional_header=pair.right }
            String rg_id_field = sub(sub(pair.right, ".*ID:", "ID:"), "\t.*", "") 
            String rg_id = sub(rg_id_field, "ID:", "")
            call samtools.addreplacerg as single_end { input: bam=add_to_bam_header.output_bam, read_group_id=rg_id }
        }
    }

    # if (pairing == "Paired-end"){
    #     Array[Pair[File, File]] fastqs = zip(bam_to_fastqs.read1s, bam_to_fastqs.read2s)
    #     scatter(pair in zip(fastqs, format_rg_for_bwa.formatted_rg)){
    #         call bwa.bwa_aln_pe as paired_end {
    #             input:
    #                 fastq1=pair.left.left,
    #                 fastq2=pair.left.right,
    #                 bwadb_tar_gz=bwadb_tar_gz,
    #                 read_group=pair.right,
    #                 max_retries=max_retries,
    #                 detect_nproc=detect_nproc
    #         }
    #     }
    # }

    Array[File] aligned_bams = select_first([single_end.tagged_bam, []])#paired_end.bam])

    scatter(bam in aligned_bams){
       call picard.clean_sam as picard_clean { input: bam=bam }
    }

    call picard.merge_sam_files as picard_merge { input: bam=picard_clean.cleaned_bam, output_name=output_prefix + ".bam" }

    call seaseq_samtools.markdup { input: bamfile=picard_merge.merged_bam, outputfile=output_prefix + ".bam" }
    call samtools.index as samtools_index { input: bam=markdup.mkdupbam, max_retries=max_retries, detect_nproc=detect_nproc }
    call picard.validate_bam { input: bam=markdup.mkdupbam, max_retries=max_retries }

    call deeptools.bamCoverage as deeptools_bamCoverage { input: bam=markdup.mkdupbam, bai=samtools_index.bai, prefix=output_prefix, max_retries=max_retries }

    output {
        File bam = markdup.mkdupbam
        File bam_index = samtools_index.bai
        File bigwig = deeptools_bamCoverage.bigwig
    }
}

task parse_input {
    input {
        String pairing
    }

    command <<<
        if [ "~{pairing}" != "Single-end" ] && [ "~{pairing}" != "Paired-end" ]; then
            >&2 echo "pairing must be either 'Single-end' or 'Paired-end'"
            exit 1
        fi
    >>>

    runtime {
        disk: "1 GB"
        docker: 'ghcr.io/stjudecloud/util:1.1.0'
    }

    output {
        String input_check = "passed"
    }
}
