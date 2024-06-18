version 1.1

import "../../tools/deeptools.wdl"
import "../../tools/htseq.wdl"
import "../../tools/ngsderive.wdl"
import "../../tools/star.wdl"
import "../general/alignment-post.wdl" as alignment_post_wf

workflow rnaseq_core {
    meta {
        description: "Main processing of RNA-Seq data, starting with FASTQs. We recommend against calling this workflow directly, and would suggest instead running `rnaseq_standard` or `rnaseq_standard_fastq`. Both wrapper workflows provide a nicer user experience than this workflow and will get you equivalent results."
        outputs: {
            bam: "Harmonized RNA-Seq BAM",
            bam_index: "BAI index file associated with `bam`",
            bam_checksum: "STDOUT of the `md5sum` command run on the harmonized BAM that has been redirected to a file",
            star_log: "Summary mapping statistics after mapping job is complete",
            bigwig: "BigWig format coverage file generated from `bam`",
            feature_counts: "A two column headerless TSV file. First column is feature names and second column is counts.",
            inferred_strandedness: "TSV file containing the `ngsderive strandedness` report",
            inferred_strandedness_string: "Derived strandedness from `ngsderive strandedness`"
        }
        allowNestedInputs: true
    }

    parameter_meta {
        read_one_fastqs_gz: "Input gzipped FASTQ format file(s) with 1st read in pair to align"
        read_two_fastqs_gz: "Input gzipped FASTQ format file(s) with 2nd read in pair to align"
        gtf: "Gzipped GTF feature file"
        star_db: "Database of reference files for the STAR aligner. The name of the root directory which was archived must match the archive's filename without the `.tar.gz` extension. Can be generated by `star-db-build.wdl`"
        read_groups: "A string containing the read group information to output in the BAM file. If including multiple read group fields per-read group, they should be space delimited. Read groups should be comma separated, with a space on each side (i.e. ' , '). The ID field must come first for each read group and must be contained in the basename of a FASTQ file or pair of FASTQ files if Paired-End. Example: `ID:rg1 PU:flowcell1.lane1 SM:sample1 PL:illumina LB:sample1_lib1 , ID:rg2 PU:flowcell1.lane2 SM:sample1 PL:illumina LB:sample1_lib1`. These two read groups could be associated with the following four FASTQs: `sample1.rg1_R1.fastq,sample1.rg2_R1.fastq` and `sample1.rg1_R2.fastq,sample1.rg2_R2.fastq`"
        prefix: "Prefix for output files"
        contaminant_db: "A compressed reference database corresponding to the aligner chosen with `xenocp_aligner` for the contaminant genome"
        align_sj_stitch_mismatch_n_max: {
            description: "This overrides the STAR alignment default. Maximum number of mismatches for stitching of the splice junctions (-1: no limit) for: (1) non-canonical motifs, (2) GT/AG and CT/AC motif, (3) GC/AG and CT/GC motif, (4) AT/AC and GT/AT motif",
            tool: "star",
            tool_default: {
                noncanonical_motifs: 0,
                GT_AG_and_CT_AC_motif: "-1", # TODO: remove quotes once sprocket supports negative integers
                GC_AG_and_CT_GC_motif: 0,
                AT_AC_and_GT_AT_motif: 0
            }
        }
        xenocp_aligner: {
            description: "Aligner to use to map reads to the host genome for detecting contamination",
            choices: [
                "bwa aln",
                "bwa mem",
                "star"
            ]
        }
        strandedness: {
            description: "Strandedness protocol of the RNA-Seq experiment. If unspecified, strandedness will be inferred by `ngsderive`.",
            choices: [
                "",
                "Stranded-Reverse",
                "Stranded-Forward",
                "Unstranded"
            ]
        }
        mark_duplicates: "Add SAM flag to computationally determined duplicate reads?"
        cleanse_xenograft: "If true, use XenoCP to unmap reads from contaminant genome"
        use_all_cores: "Use all cores for multi-core steps?"
        align_spliced_mate_map_l_min_over_l_mate: {
            description: "This overrides the STAR alignment default. alignSplicedMateMapLmin normalized to mate length",
            tool: "star",
            tool_default: 0.66
        }
        out_filter_multimap_n_max: {
            description: "This overrides the STAR alignment default. Maximum number of loci the read is allowed to map to. Alignments (all of them) will be output only if the read maps to no more loci than this value. Otherwise no alignments will be output, and the read will be counted as 'mapped to too many loci' in the Log.final.out.",
            tool: "star",
            tool_default: 10,
            common: true
        }
        pe_overlap_n_bases_min: {
            description: "This overrides the STAR alignment default. Minimum number of overlap bases to trigger mates merging and realignment. Specify >0 value to switch on the 'merging of overlapping mates' algorithm.",
            tool: "star",
            tool_default: 0
        }
        chim_score_separation: {
            description: "This overrides the STAR alignment default. Minimum difference (separation) between the best chimeric score and the next one",
            tool: "star",
            tool_default: 10
        }
        chim_score_junction_nonGTAG: {
            description: "This overrides the STAR alignment default. Penalty for a non-GT/AG chimeric junction",
            tool: "star",
            tool_default: "-1" # TODO: remove quotes once sprocket supports negative integers
        }
        chim_junction_overhang_min: {
            description: "This overrides the STAR alignment default. Minimum overhang for a chimeric junction",
            tool: "star",
            tool_default: 20,
            common: true
        }
        chim_segment_read_gap_max: {
            description: "This overrides the STAR alignment default. Maximum gap in the read sequence between chimeric segments",
            tool: "star",
            tool_default: 0,
            common: true
        }
        chim_multimap_n_max: {
            description: "This overrides the STAR alignment default. Maximum number of chimeric multi-alignments. `0`: use the old scheme for chimeric detection which only considered unique alignments",
            tool: "star",
            tool_default: 0,
            common: true
        }
        chim_score_drop_max: {
            description: "max drop (difference) of chimeric score (the sum of scores of all chimeric segments) from the read length",
            tool: "star",
            tool_default: 20,
            common: true
        }
    }

    input {
        File gtf
        File star_db
        Array[File] read_one_fastqs_gz
        Array[File] read_two_fastqs_gz
        String read_groups
        String prefix
        File? contaminant_db
        SpliceJunctionMotifs align_sj_stitch_mismatch_n_max = SpliceJunctionMotifs {
            noncanonical_motifs: 5,
            GT_AG_and_CT_AC_motif: -1,
            GC_AG_and_CT_GC_motif: 5,
            AT_AC_and_GT_AT_motif: 5
        }
        String xenocp_aligner = "star"
        String strandedness = ""
        Boolean mark_duplicates = false
        Boolean cleanse_xenograft = false
        Boolean use_all_cores = false
        Float align_spliced_mate_map_l_min_over_l_mate = 0.5
        Int out_filter_multimap_n_max = 50
        Int pe_overlap_n_bases_min = 10
        Int chim_score_separation = 1
        Int chim_score_junction_nonGTAG = 0
        Int chim_junction_overhang_min = 10
        Int chim_segment_read_gap_max = 3
        Int chim_multimap_n_max = 50
        Int chim_score_drop_max = 30
    }

    Map[String, String] htseq_strandedness_map = {
        "Stranded-Reverse": "reverse",
        "Stranded-Forward": "yes",
        "Unstranded": "no",
        "Inconclusive": "undefined",
        "": "undefined"
    }

    String provided_strandedness = strandedness

    call star.alignment { input:
        read_one_fastqs_gz,
        read_two_fastqs_gz,
        star_db_tar_gz=star_db,
        prefix,
        read_groups,
        use_all_cores,
        align_sj_stitch_mismatch_n_max,
        out_filter_multimap_n_max,
        pe_overlap_n_bases_min,
        chim_score_separation,
        chim_score_junction_nonGTAG,
        chim_junction_overhang_min,
        chim_segment_read_gap_max,
        chim_multimap_n_max,
        align_spliced_mate_map_l_min_over_l_mate,
        chim_score_drop_max,
    }

    call alignment_post_wf.alignment_post { input:
        bam=alignment.star_bam,
        mark_duplicates=mark_duplicates,
        contaminant_db=contaminant_db,
        cleanse_xenograft=cleanse_xenograft,
        xenocp_aligner=xenocp_aligner,
        use_all_cores=use_all_cores,
    }

    call deeptools.bam_coverage as deeptools_bam_coverage { input:
        bam=alignment_post.processed_bam,
        bam_index=alignment_post.bam_index,
        use_all_cores=use_all_cores,
    }

    call ngsderive.strandedness as ngsderive_strandedness { input:
        bam=alignment_post.processed_bam,
        bam_index=alignment_post.bam_index,
        gene_model=gtf,
    }

    String htseq_strandedness = if (provided_strandedness != "")
        then htseq_strandedness_map[provided_strandedness]
        else htseq_strandedness_map[ngsderive_strandedness.strandedness_string]

    call htseq.count as htseq_count { input:
        bam=alignment_post.processed_bam,
        gtf=gtf,
        strandedness=htseq_strandedness,
        prefix=basename(alignment_post.processed_bam, "bam")
            + (
                if provided_strandedness == ""
                then ngsderive_strandedness.strandedness_string
                else provided_strandedness
            ),
    }

    output {
        File bam = alignment_post.processed_bam
        File bam_index = alignment_post.bam_index
        File bam_checksum = alignment_post.bam_checksum
        File star_log = alignment.star_log
        File bigwig = deeptools_bam_coverage.bigwig
        File feature_counts = htseq_count.feature_counts
        File inferred_strandedness = ngsderive_strandedness.strandedness_file
        String inferred_strandedness_string = ngsderive_strandedness.strandedness_string
    }
}
