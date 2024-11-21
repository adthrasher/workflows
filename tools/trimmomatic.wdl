version 1.0

task trimmomatic {
    meta {
        description: "Trimmomatic is a flexible read trimming tool for Illumina NGS data."
        help: "Trimmomatic performs a variety of useful trimming tasks for Illumina paired-end and single-end data."
        outputs: {
            trimmed_reads: "Trimmed reads in FASTQ format"
        }
    }

    parameter_meta {
        input_reads: "Input FASTQ file(s) to be trimmed"
        adapters: "FASTA file of adapter sequences to be removed"
        leading: "Remove leading low quality or N bases"
        trailing: "Remove trailing low quality or N bases"
        slidingwindow: "Perform sliding window trimming, cutting once the average quality within the window falls below a threshold"
        minlen: "Drop reads below the specified length"
        threads: "Number of threads to use for trimming"
    }

    input {
        Array[File] input_reads
        File adapters
        Int leading = 3
        Int trailing = 3
        Int slidingwindow = 4
        Int minlen = 36
        Int threads = 1
    }

    command <<<
        trimmomatic SE -phred33 \
            ~{sep(" ", input_reads)} \
            trimmed_reads.fastq \
            ILLUMINACLIP:~{adapters}:2:30:10 \
            LEADING:~{leading} \
            TRAILING:~{trailing} \
            SLIDINGWINDOW:~{slidingwindow}:20 \
            MINLEN:~{minlen} \
            -threads ~{threads}
    >>>

    output {
        File trimmed_reads = "trimmed_reads.fastq"
    }

    runtime {
        docker: "quay.io/biocontainers/trimmomatic:0.39--hdfd78af_2"
        memory: "4 GB"
        cpu: threads
    }
}
