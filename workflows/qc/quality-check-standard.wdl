## # Quality Check Standard
##
## This workflow runs a variety of quality checking software on any BAM file.
## It can be WGS, WES, or Transcriptome data. The results are aggregated and
## run through [MultiQC](https://multiqc.info/).
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

import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/md5sum.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/picard.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/samtools.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/fastqc.wdl" as fqc
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/ngsderive.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/qualimap.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/fq.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/fastq_screen.wdl" as fq_screen
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/sequencerr.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/multiqc.wdl" as mqc

workflow quality_check {
    input {
        File bam
        File bam_index
        File? gtf
        File? star_log
        String experiment
        String strandedness = ""
        File? fastq_screen_db
        String phred_encoding = ""
        Boolean paired_end = true
        Boolean illumina = true
        Int max_retries = 1
    }

    parameter_meta {
        bam: "Input BAM format file to quality check"
        bam_index: "BAM index file corresponding to the input BAM"
        gtf: "GTF features file. **Required** for RNA-Seq data"
        star_log: "Log file generated by the RNA-Seq aligner STAR"
        experiment: "'WGS', 'WES', 'RNA-Seq', or 'ChIP-Seq'"
        strandedness: "empty, 'Stranded-Reverse', 'Stranded-Forward', or 'Unstranded'. Only needed for RNA-Seq data. If missing, will be inferred"
        fastq_screen_db: "Database for FastQ Screen. **Required** for WGS and WES data. Can be generated using `make-qc-reference.wdl`. Must untar directly to genome directories."
        phred_encoding: "Encoding format used for PHRED quality scores. Must be empty, 'sanger', or 'illumina1.3'. Only needed for WGS/WES. If missing, will be inferred"
        paired_end: "Whether the data is paired end"
        illumina: "Sequenced by an Illumina machine? `sequencErr` only supports Illumina formatted reads. Non-Illumina data may cause errors. Only used for WGS/WES"
        max_retries: "Number of times to retry failed steps"
    }

    String prefix = basename(bam, ".bam")
    String provided_strandedness = strandedness

    call parse_input {
        input:
            input_experiment=experiment,
            input_gtf=gtf,
            input_strand=provided_strandedness,
            input_fq_format=phred_encoding
    }

    call md5sum.compute_checksum { input: infile=bam, max_retries=max_retries }

    call picard.validate_bam { input: bam=bam, succeed_on_errors=true, ignore_list=[], summary_mode=true, max_retries=max_retries }
    call samtools.quickcheck { input: bam=bam, max_retries=max_retries }

    call samtools.flagstat as samtools_flagstat { input: bam=quickcheck.checked_bam, max_retries=max_retries }
    call fqc.fastqc { input: bam=quickcheck.checked_bam, max_retries=max_retries }
    call ngsderive.instrument as ngsderive_instrument { input: bam=quickcheck.checked_bam, max_retries=max_retries }
    call ngsderive.read_length as ngsderive_read_length { input: bam=quickcheck.checked_bam, bai=bam_index, max_retries=max_retries }
    call ngsderive.encoding as ngsderive_encoding { input: ngs_files=[quickcheck.checked_bam], prefix=prefix, max_retries=max_retries }
    String parsed_encoding = read_string(ngsderive_encoding.inferred_encoding)
    call qualimap.bamqc as qualimap_bamqc { input: bam=quickcheck.checked_bam, max_retries=max_retries }

    if (experiment == "WGS" || experiment == "WES") {
        File fastq_screen_db_defined = select_first([fastq_screen_db, "No DB"])

        if (illumina) {
            call sequencerr.sequencerr as sequencErr { input: bam=quickcheck.checked_bam, bai=bam_index, max_retries=max_retries }
        }

        call samtools.subsample as samtools_subsample { input: bam=quickcheck.checked_bam, max_retries=max_retries }
        call picard.bam_to_fastq { input: bam=samtools_subsample.sampled_bam, max_retries=max_retries }
        call fq.fqlint { input: read1=bam_to_fastq.read1, read2=bam_to_fastq.read2, max_retries=max_retries }
        call fq_screen.fastq_screen { input: read1=fqlint.validated_read1, read2=select_first([fqlint.validated_read2, ""]), db=fastq_screen_db_defined, provided_encoding=phred_encoding, inferred_encoding=parsed_encoding, max_retries=max_retries }
        
        call mqc.multiqc as multiqc_wgs {
            input:
                validate_sam_file=validate_bam.out,
                flagstat_file=samtools_flagstat.outfile,
                fastqc=fastqc.results,
                instrument_file=ngsderive_instrument.instrument_file,
                read_length_file=ngsderive_read_length.read_length_file,
                encoding_file=ngsderive_encoding.encoding_file,
                qualimap_bamqc=qualimap_bamqc.results,
                fastq_screen=fastq_screen.results,
                max_retries=max_retries
        }
    }
    if (experiment == "RNA-Seq") {
        File gtf_defined = select_first([gtf, "No GTF"])

        call ngsderive.junction_annotation as junction_annotation { input: bam=quickcheck.checked_bam, bai=bam_index, gtf=gtf_defined, max_retries=max_retries }

        call ngsderive.infer_strandedness as ngsderive_strandedness { input: bam=quickcheck.checked_bam, bai=bam_index, gtf=gtf_defined, max_retries=max_retries }
        String parsed_strandedness = read_string(ngsderive_strandedness.strandedness)
        call qualimap.rnaseq as qualimap_rnaseq { input: bam=quickcheck.checked_bam, gtf=gtf_defined, provided_strandedness=provided_strandedness, inferred_strandedness=parsed_strandedness, paired_end=paired_end, max_retries=max_retries }

        call mqc.multiqc as multiqc_rnaseq {
            input:
                validate_sam_file=validate_bam.out,
                star_log=star_log,
                flagstat_file=samtools_flagstat.outfile,
                fastqc=fastqc.results,
                instrument_file=ngsderive_instrument.instrument_file,
                read_length_file=ngsderive_read_length.read_length_file,
                encoding_file=ngsderive_encoding.encoding_file,
                strandedness_file=ngsderive_strandedness.strandedness_file,
                junction_annotation=junction_annotation.junction_summary,
                qualimap_bamqc=qualimap_bamqc.results,
                qualimap_rnaseq=qualimap_rnaseq.results,
                max_retries=max_retries
        }
    }
    if (experiment == "ChIP-Seq") {
        call mqc.multiqc as multiqc_chipseq {
            input:
                validate_sam_file=validate_bam.out,
                flagstat_file=samtools_flagstat.outfile,
                fastqc=fastqc.results,
                instrument_file=ngsderive_instrument.instrument_file,
                read_length_file=ngsderive_read_length.read_length_file,
                encoding_file=ngsderive_encoding.encoding_file,
                qualimap_bamqc=qualimap_bamqc.results,
                max_retries=max_retries
        }
    }

    output {
        File bam_checksum = compute_checksum.outfile
        File validate_sam_file = validate_bam.out
        File flagstat = samtools_flagstat.outfile
        File fastqc_results = fastqc.results
        File instrument_file = ngsderive_instrument.instrument_file
        File read_length_file = ngsderive_read_length.read_length_file
        File qualimap_bamqc_results = qualimap_bamqc.results
        File inferred_encoding = ngsderive_encoding.encoding_file
        File? fastq_screen_results = fastq_screen.results
        File? sequencerr_results = sequencErr.results
        File? inferred_strandedness = ngsderive_strandedness.strandedness_file
        File? qualimap_rnaseq_results = qualimap_rnaseq.results
        File? junction_summary = junction_annotation.junction_summary
        File? junctions = junction_annotation.junctions
        File? multiqc_wgs_zip = multiqc_wgs.out
        File? multiqc_rnaseq_zip = multiqc_rnaseq.out
        File? multiqc_chipseq_zip = multiqc_chipseq.out
    }
}

task parse_input {
    input {
        String input_experiment
        File? input_gtf
        String input_strand
        String input_fq_format
    }

    String no_gtf = if defined(input_gtf) then "" else "true"

    command <<<
        EXITCODE=0
        if [ "~{input_experiment}" != "WGS" ] && [ "~{input_experiment}" != "WES" ] && [ "~{input_experiment}" != "RNA-Seq" ] && [ "~{input_experiment}" != "ChIP-Seq" ]; then
            >&2 echo "experiment input must be 'WGS', 'WES', 'RNA-Seq', or 'ChIP-Seq"
            EXITCODE=1
        fi

        if [ "~{input_experiment}" = "RNA-Seq" ] && [ "~{no_gtf}" = "true" ]; then
            >&2 echo "Must supply a GTF if experiment = 'RNA-Seq'"
            EXITCODE=1
        fi

        if [ -n "~{input_strand}" ] && [ "~{input_strand}" != "Stranded-Reverse" ] && [ "~{input_strand}" != "Stranded-Forward" ] && [ "~{input_strand}" != "Unstranded" ]; then
            >&2 echo "strandedness must be empty, 'Stranded-Reverse', 'Stranded-Forward', or 'Unstranded'"
            EXITCODE=1
        fi

        if [ -n "~{input_fq_format}" ] && [ "~{input_fq_format}" != "sanger" ] && [ "~{input_fq_format}" != "illunima1.3" ]; then
            >&2 echo "phred_encoding must be empty, 'sanger', or 'illumina1.3'"
            EXITCODE=1
        fi
        exit $EXITCODE
    >>>

    runtime {
        disk: "5 GB"
        docker: 'ghcr.io/stjudecloud/util:1.0.0'
    }

    output {
        String input_check = "passed"
    }
}
