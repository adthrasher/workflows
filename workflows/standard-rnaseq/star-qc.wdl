## Description: 
##
## This WDL workflow runs a set of QC steps on an output STAR BAM file.  
##
## Inputs: 
##
## bam - the BAM generated by STAR 
##
## LICENSING :
## MIT License
##
## Copyright 2019 St. Jude Children's Research Hospital
##
## Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
##
##The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
##
##THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import "https://raw.githubusercontent.com/stjudecloud/workflows/jobin/rnaseq_v2_azure/tools/qc.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/jobin/rnaseq_v2_azure/tools/samtools.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/jobin/rnaseq_v2_azure/tools/picard.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/jobin/rnaseq_v2_azure/tools/fastqc.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/jobin/rnaseq_v2_azure/tools/qualimap.wdl"

workflow star_qc {
    File bam
    Int ncpu

    call samtools.quickcheck { input: bam=bam }
    call picard.validate_bam { input: bam=bam }
    call fastqc.fastqc { input: bam=bam, ncpu=ncpu }
    call qualimap.bamqc { input: bam=bam, ncpu=ncpu }
}
