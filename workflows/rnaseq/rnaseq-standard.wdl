## # RNA-Seq Standard
##
## This WDL workflow runs the STAR RNA-Seq alignment workflow for St. Jude Cloud.
##
## The workflow takes an input BAM file and splits it into FastQ files for each read in the pair. 
## The read pairs are then passed through STAR alignment to generate a BAM file.
## In the case of xenograft samples, the resulting BAM can be optionally cleansed
## with our XenoCP workflow.
## Quantification is done using htseq-count. Coverage is calculated with DeepTools.
## Strandedness is inferred using ngsderive.
## File validation is performed at several steps, including immediately preceeding output.
##
## ## LICENSING
##
## #### MIT License
##
## Copyright 2020-Present St. Jude Children's Research Hospital
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

import "../general/bam-to-fastqs.wdl" as b2fq
import "../../tools/picard.wdl"
import "../../tools/samtools.wdl"
import "../../tools/util.wdl"
import "./rnaseq-core.wdl" as rna_core

workflow rnaseq_standard {
    input {
        File bam
        String output_prefix = basename(bam, ".bam")
        File gtf
        File stardb
        Boolean mark_duplicates = false
        Int subsample_n_reads = -1
        File? contaminant_db
        Boolean cleanse_xenograft = false
        String xenocp_aligner = "star"
        String strandedness = ""
        Boolean validate_input = true
        Boolean use_all_cores = false
        Int? max_retries
    }

    parameter_meta {
        bam: "Input BAM format file to harmonize"
        output_prefix: "Prefix for output files"
        gtf: "Gzipped GTF feature file"
        stardb: "Database of reference files for the STAR aligner. The name of the root directory which was archived must match the archive's filename without the `.tar.gz` extension. Can be generated by `star-db-build.wdl`"
        mark_duplicates: "Add SAM flag to computationally determined duplicate reads?"
        subsample_n_reads: "Only process a random sampling of `n` reads. Any `n`<=`0` for processing entire input."
        contaminant_db: "A compressed reference database corresponding to the aligner chosen with `xenocp_aligner` for the contaminant genome"
        cleanse_xenograft: "If true, use XenoCP to unmap reads from contaminant genome"
        xenocp_aligner: {
            description: "Aligner to use to map reads to the host genome for detecting contamination"
            choices: [
                'bwa aln',
                'bwa mem',
                'star'
            ]
        },
        strandedness: {
            description: "Strandedness protocol of the RNA-Seq experiment. If unspecified, strandedness will be inferred by `ngsderive`."
            choices: [
                '',
                'Stranded-Reverse',
                'Stranded-Forward',
                'Unstranded'
            ]
        },
        validate_input: "Ensure input BAM is well-formed before beginning harmonization"
        use_all_cores: "Use all cores for multi-core steps?"
        max_retries: "Number of times to retry failed steps. Overrides task level defaults."
    }

    call parse_input { input:
        input_strand=strandedness,
        cleanse_xenograft=cleanse_xenograft,
        contaminant_db=defined(contaminant_db)
    }

    if (validate_input) {
       call picard.validate_bam as validate_input_bam { input: bam=bam, max_retries=max_retries }
    }

    if (subsample_n_reads > 0) {
        call samtools.subsample { input:
            bam=bam,
            max_retries=max_retries,
            desired_reads=subsample_n_reads,
            use_all_cores=use_all_cores
        }
    }
    File selected_input_bam = select_first([subsample.sampled_bam, bam])

    call util.get_read_groups { input: bam=selected_input_bam, max_retries=max_retries }
    String read_groups = read_string(get_read_groups.read_groups_file)
    call b2fq.bam_to_fastqs { input:
        bam=selected_input_bam,
        paired_end=true,  # matches default but prevents user from overriding
        use_all_cores=use_all_cores,
        max_retries=max_retries
    }

    call rna_core.rnaseq_core { input:
        read_one_fastqs=bam_to_fastqs.read1s,
        read_two_fastqs=select_all(bam_to_fastqs.read2s),
        read_groups=read_groups,
        output_prefix=output_prefix,
        gtf=gtf,
        stardb=stardb,
        mark_duplicates=mark_duplicates,
        contaminant_db=contaminant_db,
        cleanse_xenograft=cleanse_xenograft,
        xenocp_aligner=xenocp_aligner,
        strandedness=strandedness,
        use_all_cores=use_all_cores,
        max_retries=max_retries
    }

    output {
        File harmonized_bam = rnaseq_core.bam
        File bam_index = rnaseq_core.bam_index
        File bam_checksum = rnaseq_core.bam_checksum
        File star_log = rnaseq_core.star_log
        File feature_counts = rnaseq_core.feature_counts
        File inferred_strandedness = rnaseq_core.inferred_strandedness
        String inferred_strandedness_string = rnaseq_core.inferred_strandedness_string
        File bigwig = rnaseq_core.bigwig
    }
}

task parse_input {
    input {
        String input_strand
        Boolean cleanse_xenograft
        Boolean contaminant_db
    }

    command {
        if [ -n "~{input_strand}" ] && [ "~{input_strand}" != "Stranded-Reverse" ] && [ "~{input_strand}" != "Stranded-Forward" ] && [ "~{input_strand}" != "Unstranded" ]; then
            >&2 echo "strandedness must be empty, 'Stranded-Reverse', 'Stranded-Forward', or 'Unstranded'"
            exit 1
        fi
        if [ "~{cleanse_xenograft}" == "true" ] && [ "~{contaminant_db}" == "false" ]
        then
            >&2 echo "'contaminant_db' must be supplied if 'cleanse_xenograft' is 'true'"
            exit 1
        fi
    }

    runtime {
        memory: "4 GB"
        disk: "1 GB"
        docker: 'ghcr.io/stjudecloud/util:1.2.0'
    }

    output {
        String input_check = "passed"
    }
}
