#!/bin/bash
#PBS -q par128
#PBS -N fasterq_AD_WXS_YES
#PBS -o fasterq_AD_WXS_YES.out
#PBS -e fasterq_AD_WXS_YES.err
#PBS -l select=1:ncpus=128

cd $PBS_O_WORKDIR
cd /path/to/your/home/your_name

module load miniconda3/4.10.3-intel-2021.3.0
source activate bioinfo2

cd /path/to/your/home/your_name/AD_WXS/AD_WXS_YES

SRR_LIST="SRRXXXXXXX SRRYYYYYYY SRRZZZZZZZ ..."

for srr in $SRR_LIST; do
    if [[ -f "$srr/${srr}_1.fastq" && -f "$srr/${srr}_2.fastq" ]]; then
        echo "Arquivos FASTQ já existem para: $srr. Pulando..."
        continue
    fi

    rm -rf "${srr}/fasterq.tmp."*

    echo "Processando: $srr/$srr.sra"
    (cd "$srr" && fasterq-dump --split-files --threads 16 --outdir . "$srr.sra")

    if [ $? -eq 0 ]; then
        echo "Sucesso: $srr processado"
    else
        echo "Erro: Falha ao processar $srr" >&2
    fi
done

echo ""
echo "Verificação final:"
for srr in $SRR_LIST; do
    if [[ -f "$srr/${srr}_1.fastq" ]]; then
        echo "  $srr: OK"
    else
        echo "  $srr: FALTANDO"
    fi
done
