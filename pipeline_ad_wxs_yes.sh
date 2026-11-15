#!/bin/bash
#PBS -q par128
#PBS -N pipeline_AD_WXS_YES
#PBS -o pipeline_AD_WXS_YES.out
#PBS -e pipeline_AD_WXS_YES.err
#PBS -l select=1:ncpus=128

cd $PBS_O_WORKDIR
cd /path/to/your/home/

module load miniconda3/4.10.3-intel-2021.3.0
source activate bioinfo2

GRUPO="AD_WXS_YES"
BASE_DIR="path/to/your/AD_WXS/AD_WXS_YES"
REF="path/to/your/genome.fa"
GATK_RES="path/to/your/gatk_resources"
DBSNP="$GATK_RES/Homo_sapiens_assembly38.dbsnp138.vcf.gz"
MILLS="$GATK_RES/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz"
KG="$GATK_RES/1000G_phase1.snps.high_confidence.hg38.vcf.gz"

SRR_LIST="SRRXXXXXXX SRRYYYYYYY SRRZZZZZZZ ..."

echo "=================================================="
echo "Iniciando pipeline para o grupo: $GRUPO"
echo "=================================================="

cd "$BASE_DIR"

for srr in $SRR_LIST; do
    echo ""
    echo "########## Processando amostra: $srr ##########"

    if [[ ! -d "$srr" ]]; then
        echo "AVISO: pasta $srr não encontrada. Pulando."
        continue
    fi

    cd "$srr"

    if [[ -f "${srr}_1.fastq.gz" ]]; then
        R1="${srr}_1.fastq.gz"; R2="${srr}_2.fastq.gz"
    elif [[ -f "${srr}_1.fastq" ]]; then
        R1="${srr}_1.fastq"; R2="${srr}_2.fastq"
    else
        echo "AVISO: FASTQ não encontrado para $srr. Pulando."
        cd "$BASE_DIR"
        continue
    fi

    if [[ -f "${srr}_trim_1.fastq.gz" && -f "${srr}_trim_2.fastq.gz" ]]; then
        echo "[1/5] fastp já feito. Pulando."
    else
        echo "[1/5] Rodando fastp..."
        fastp -i "$R1" -I "$R2" \
            -o "${srr}_trim_1.fastq.gz" -O "${srr}_trim_2.fastq.gz" \
            --detect_adapter_for_pe \
            --cut_right --cut_right_window_size 4 --cut_right_mean_quality 20 \
            --length_required 50 -q 15 -u 40 \
            -j "${srr}.fastp.json" -h "${srr}.fastp.html" --thread 16
    fi

    if [[ -f "${srr}.sorted.bam" ]]; then
        echo "[2/5] Alinhamento já feito. Pulando."
    else
        echo "[2/5] Rodando BWA-MEM2 + samtools sort..."
        bwa-mem2 mem -t 16 \
            -R "@RG\tID:${srr}\tSM:${srr}\tPL:ILLUMINA\tLB:${srr}" \
            "$REF" "${srr}_trim_1.fastq.gz" "${srr}_trim_2.fastq.gz" | \
            samtools sort -@ 16 -m 2G -o "${srr}.sorted.bam" -
        samtools index "${srr}.sorted.bam"
    fi

    if [[ -f "${srr}.dedup.bam" ]]; then
        echo "[3/5] MarkDuplicates já feito. Pulando."
    else
        echo "[3/5] Rodando MarkDuplicates..."
        gatk --java-options "-Xmx48g" MarkDuplicates \
            -I "${srr}.sorted.bam" -O "${srr}.dedup.bam" -M "${srr}.dedup.metrics.txt"
        samtools index "${srr}.dedup.bam"
    fi

    if [[ -f "${srr}.bqsr.bam" ]]; then
        echo "[4/5] BQSR já feito. Pulando."
    else
        echo "[4/5] Rodando BaseRecalibrator + ApplyBQSR..."
        gatk --java-options "-Xmx48g" BaseRecalibrator \
            -R "$REF" -I "${srr}.dedup.bam" \
            --known-sites "$DBSNP" --known-sites "$MILLS" --known-sites "$KG" \
            -O "${srr}.recal.table"
        gatk --java-options "-Xmx48g" ApplyBQSR \
            -R "$REF" -I "${srr}.dedup.bam" \
            --bqsr-recal-file "${srr}.recal.table" -O "${srr}.bqsr.bam"
    fi

    if [[ -f "${srr}.g.vcf.gz" ]]; then
        echo "[5/5] HaplotypeCaller já feito. Pulando."
    else
        echo "[5/5] Rodando HaplotypeCaller (GVCF)..."
        gatk --java-options "-Xmx48g" HaplotypeCaller \
            -R "$REF" -I "${srr}.bqsr.bam" -O "${srr}.g.vcf.gz" \
            -ERC GVCF --native-pair-hmm-threads 16
    fi

    echo "Amostra $srr concluída."
    cd "$BASE_DIR"
done

echo ""
echo "=================================================="
echo "Todas as amostras processadas. Iniciando junção final (${GRUPO})"
echo "=================================================="

GVCF_ARGS=""
for srr in $SRR_LIST; do
    if [[ -f "$BASE_DIR/$srr/${srr}.g.vcf.gz" ]]; then
        GVCF_ARGS="$GVCF_ARGS -V $BASE_DIR/$srr/${srr}.g.vcf.gz"
    else
        echo "AVISO: GVCF de $srr não encontrado, será excluído da junção."
    fi
done

if [[ -z "$GVCF_ARGS" ]]; then
    echo "ERRO: nenhum GVCF disponível para junção. Abortando etapa final."
    exit 1
fi

echo "Rodando CombineGVCFs..."
gatk --java-options "-Xmx48g" CombineGVCFs \
    -R "$REF" \
    $GVCF_ARGS \
    -O "$BASE_DIR/${GRUPO}_combined.g.vcf.gz"

echo "Rodando GenotypeGVCFs..."
gatk --java-options "-Xmx48g" GenotypeGVCFs \
    -R "$REF" \
    -V "$BASE_DIR/${GRUPO}_combined.g.vcf.gz" \
    -O "$BASE_DIR/${GRUPO}_joint_genotyped.vcf.gz"

echo ""
echo "Pipeline completo para o grupo ${GRUPO}."
echo "VCF final: $BASE_DIR/${GRUPO}_joint_genotyped.vcf.gz"
