## [Homepage](https://bioinformatics.mdanderson.org/estimate/)
#
# SPDX-License-Identifier: MIT
# Copyright St. Jude Children's Research Hospital
version 1.1

task calc_tpm {
    meta {
        description: "Given a gene counts file and a gene lengths file, calculate Transcripts Per Million (TPM)"
        outputs: {
            tpm_file: "Transcripts Per Million (TPM) file. A two column headered TSV file."
        }
    }

    parameter_meta {
        counts: "A two column headerless TSV file with gene names in the first column and counts (as integers) in the second column. Entries starting with '__' will be discarded. Can be generated with `htseq.wdl`."
        gene_lengths: "A two column headered TSV file with gene names (matching those in the `counts` file) in the first column and feature lengths (as integers) in the second column. Can be generated with `calc-gene-lengths.wdl`."
        prefix: "Prefix for the TPM file. The extension `.TPM.txt` will be added."
        memory_gb: "RAM to allocate for task, specified in GB"
        disk_size_gb: "Disk space to allocate for task, specified in GB"
        max_retries: "Number of times to retry in case of failure"
    }

    input {
        File counts
        File gene_lengths
        String prefix = basename(counts, ".feature-counts.txt")
        Int memory_gb = 4
        Int disk_size_gb = 10
        Int max_retries = 1
    }

    String outfile_name = prefix + ".TPM.txt"

    command <<<
        COUNTS="~{counts}" GENE_LENGTHS="~{gene_lengths}" OUTFILE="~{outfile_name}" python3 - <<END
import os  # lint-check: ignore

counts_file = open(os.environ['COUNTS'], 'r')
counts = {}
for line in counts_file:
    gene, count = line.split('\t')
    if gene[0:2] == '__':
        break
    counts[gene.strip()] = int(count.strip())
counts_file.close()

lengths_file = open(os.environ['GENE_LENGTHS'], 'r')
rpks = {}
tot_rpk = 0
lengths_file.readline()  # discard header
for line in lengths_file:
    gene, length = line.split('\t')
    rpk = counts[gene.strip()] / int(length.strip()) * 1000
    tot_rpk += rpk
    rpks[gene.strip()] = rpk
lengths_file.close()

sf = tot_rpk / 1000000

sample_name = '.'.join(os.environ['OUTFILE'].split('.')[:-2])  # equivalent to ~{prefix}
outfile = open(os.environ['OUTFILE'], 'w')
print(f"Gene name\t{sample_name}", file=outfile)
for gene, rpk in sorted(rpks.items()):
    tpm = rpk / sf
    print(f"{gene}\t{tpm:.3f}", file=outfile)
outfile.close()
END
    >>>

    output {
        File tpm_file = "~{outfile_name}"
    }

    runtime {
        memory: "~{memory_gb} GB"
        disk: "~{disk_size_gb} GB"
        docker: 'ghcr.io/stjudecloud/util:1.3.0'
        maxRetries: max_retries
    }
}

task run_ESTIMATE {
    meta {
        description: "Given a gene expression file, run the ESTIMATE software package"
        outputs:  {
            estimate_file: "The results file of the ESTIMATE software package"  # TODO actually run and see what format it is.
        }
    }

    parameter_meta {
        gene_expression_file: "A 2 column headered TSV file with 'Gene name' in the first column and gene expression values (as floats) in the second column. Can be generated with the `calc_tpm` task."
        outfile_name: "Name of the ESTIMATE output file"
        memory_gb: "RAM to allocate for task, specified in GB"
        disk_size_gb: "Disk space to allocate for task, specified in GB"
        max_retries: "Number of times to retry in case of failure"
    }

    input {
        File gene_expression_file
        String outfile_name = (
            basename(gene_expression_file, ".TPM.txt") + ".ESTIMATE.gct"
        )
        Int memory_gb = 4
        Int disk_size_gb = 10
        Int max_retries = 1
    }

    command <<<
        cp "~{gene_expression_file}" gene_expression.txt
        Rscript - <<END
library("estimate")

infile <- read.table(file = "gene_expression.txt", sep = '\t', header = TRUE)
filtered <- infile[infile$"Gene.name" %in% common_genes[['GeneSymbol']], ]
write.table(filtered, sep = "\t", file = "filtered.tsv", row.names = FALSE, quote = FALSE)
outputGCT("filtered.tsv", "gene_expression.gct")
estimateScore("gene_expression.gct", "common_estimate.gct", platform = "illumina")
END
    mv common_estimate.gct "~{outfile_name}"
    >>>

    output {
        File estimate_file = "~{outfile_name}"
    }

    runtime {
        memory: "~{memory_gb} GB"
        disk: "~{disk_size_gb} GB"
        docker: 'ghcr.io/stjudecloud/estimate:1.0.0'
        maxRetries: max_retries
    }
}
