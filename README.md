# SRA-to-VCF: GATK Best Practices pipeline for whole-exome sequencing on HPC

Scripts and a step-by-step notebook to process human whole-exome sequencing (WXS) data from SRA files to joint-genotyped VCFs, following the GATK Best Practices for germline short variants. Developed and run on two HPC systems: a PBS cluster (CENAPAD-SP) and a SLURM cluster (Coaraci, Unicamp).

## Workflow

1. **SRA → FASTQ**: `fasterq-dump` (SRA Toolkit)
2. **Read QC and trimming**: FastQC, MultiQC and fastp (adapters, low-quality 3' ends, short reads)
3. **Alignment**: BWA-MEM2 to GRCh38, with read groups, then `samtools sort` and `index`
4. **Duplicate marking**: GATK MarkDuplicates
5. **Base quality score recalibration**: GATK BaseRecalibrator + ApplyBQSR (dbSNP 138, Mills and 1000G gold-standard indels, 1000G phase 1 SNPs)
6. **Variant calling**: GATK HaplotypeCaller in GVCF mode (`-ERC GVCF`)
7. **Joint genotyping**: GATK CombineGVCFs + GenotypeGVCFs

Each step checks whether its output already exists and skips it, so an interrupted job can be resubmitted and will resume where it stopped.

## Files

| File | Description |
|---|---|
| `fastq_ad_wxs_yes.sh` | PBS job: converts SRA files to paired FASTQ with `fasterq-dump` |
| `pipeline_ad_wxs_yes.sh` | PBS job: FASTQ → trimmed reads → BAM → BQSR → GVCF per sample, then joint genotyping of the group |
| `sraTOvcf.ipynb` | Step-by-step notebook on a SLURM cluster, including the conda environment, interactive jobs (`srun`, `tmux`) and a joint-genotyping script |

## Requirements

Create the conda environment (also shown in the notebook):

```bash
conda create -n bioinfo2 -c conda-forge -c bioconda python=3.11 sra-tools fastqc fastp multiqc bwa-mem2 samtools bcftools htslib gatk4
conda activate bioinfo2
```

You also need the GRCh38 reference (`genome.fa` with its BWA-MEM2 index, `.fai` and `.dict`) and the GATK resource bundle files listed above.

## Usage

1. Edit the variables at the top of each script (working directory, reference and GATK resources) and the PBS/SLURM settings for your cluster.
2. Provide your sample accessions (SRR IDs). Sample lists are not included in this repository.
3. Submit the jobs, for example on PBS:

```bash
qsub fastq_ad_wxs_yes.sh
qsub pipeline_ad_wxs_yes.sh
```

## Data access

The pipeline was developed for controlled-access data from dbGaP. No individual-level data, sample identifiers or phenotypes are included in this repository. To run the pipeline, you need your own data.

## Author

Kaira Cristina Peralis Tomaz, Laboratory of Integrative Systems Biology (LABIS), University of Campinas (Unicamp), Brazil.

## License

MIT (see `LICENSE`).
