
from os.path import join, exists
import sys
import snakemake
import time


# Import config
# Load config file
#if not config:
 #   raise SystemExit(
  #      "Config not found, are you sure your profile contains a path to an "
   #     "existing configfile?"
    #)

#with open("config.yaml", "r") as config_file:
#    config = yaml.safe_load(config_file)


configfile: "config.yaml"
in_dir=config["input_dir"]
SAMPLES=glob_wildcards(in_dir+"/{sample}.fastq")
classifier=config["classifier"]
print(SAMPLES)
type="kraken"

rule all:
    input:
         #expand("in_dir"+"/filtered/{sample}.fastq",sample=SAMPLES.sample) if config["quality"]["perform"] else "",
         join(config["out_dir"],"filtered_input/SRR14307912.fastq"),
         join(config["out_dir"],"aligned_input/SRR14307912.fastq"),
         config["out_dir"]+"/classification_"+config["classifier"]+"/SRR14307912.kreport",


# Rule: Generate MultiQC report
rule multiqc:
    input:
        fastqcs=expand(in_dir+"/{sample}.fastq", sample=SAMPLES.sample)
    output:
        output_dir=directory("/multiqc_out"),
        multiqc_output="./multiqc_out/multiqc_report.html"
    shell:
        """
         fastqc -o {output.output_dir} {input.fastqcs} 
         multiqc -o {output.multiqc_output} {output.output_dir}"""


# Rule: Quality filtering with NanoFilt



rule quality_filter:
    input:
        join(in_dir,"{sample}.fastq")
    output:
        join(config["out_dir"],"filtered_input/{sample}.fastq")
    params:
        quality_threshold=config["quality"].get("threshold",0),
        headcrop=config["quality"].get("head_crop",0),
        tailcrop=config["quality"].get("tail_crop",0),
        max_length=config["quality"].get("max_length",1700),
        min_length=config["quality"].get("min_length",1200)
    run:
       shell_cmd = "NanoFilt "
       if params.quality_threshold is not None:
            shell_cmd += " -q {params.quality_threshold} "
       if params.headcrop is not None:
            shell_cmd += " --headcrop {params.headcrop} "
       if params.tailcrop is not None:
            shell_cmd += " --tailcrop {params.tailcrop} "
       if params.max_length is not None:
           shell_cmd += " --maxlength {params.max_length} "
       if params.min_length is not None:
           shell_cmd += "--length {params.min_length} "
       shell_cmd += "{input} > {output} " #; ln -s {in_dir} {output}"
       shell(shell_cmd)

        #ln -s {in_dir} {output}
        



# Rule: Align to human reference and exclude human reads + we filter resulting SAM file creating BAM file containing only the reads that did not align
# to the human genome reference
rule align_to_host:
    input:
        fastq=join(in_dir,"{sample}.fastq"),
        host_reference=config.get("host_reference")
    output:
        join(config["out_dir"],"aligned_input/{sample}.fastq")
    params:
        out_dir=join(config["out_dir"],"aligned_input")
    shell:
        """
        if [ -n "{input[host_reference]}" ]; then
            minimap2 -a -x map-ont {input[host_reference]} {input[fastq]} > {params.out_dir}/{wildcards.sample}_minimap2.sam
            samtools sort -o {params.out_dir}/{wildcards.sample}_human_reads.bam {params.out_dir}/{wildcards.sample}_minimap2.sam
            samtools view -b -f 4 {params.out_dir}/{wildcards.sample}_human_reads.bam > {params.out_dir}/{wildcards.sample}_human_reads_filter.bam 
            samtools fastq {params.out_dir}/{wildcards.sample}_human_reads_filter.bam > {output}
            rm *.bam
            rm *.sam
        fi
            """
        #ln -s {input[fastq]} {output}
         #   """

rule download_kraken_database:
    output:
        hash=join(config["kraken_options"].get("db","kraken_dbs"),"hash.k2d"),
        opts=join(config["kraken_options"].get("db","kraken_dbs"),"opts.k2d"),
        taxo=join(config["kraken_options"].get("db","kraken_dbs"),"taxo.k2d")
    params:
        db_root=config["kraken_build_options"],

        add_genome=config["kraken_build_options"].get("add_genome",0),
        method=config["kraken_build_options"]["method"],
        references=config["kraken_build_options"]["references"]
    #singularity: "singularity_env.sif"
    shell:
        """
        bash ./scripts/download_kraken2_db.sh --method {params.db_root} --references {params.references} --output_dir {params.db_root}
        """






# Rule: Index reference for Kraken2
#rule index_kraken:
#    output:
#        hash="{kraken_db}/hash.k2d",
#        opts= "{kraken_db}/opts.k2d",
#        taxo="{kraken_db}/taxo.k2d"
#
#    params:
#        db_path=config["kraken_options"].get("db", "kraken_dbs"),
#        collection=config["kraken_build_options"]["collection"]
#    shell:
#        """
#            list=("greengenes" "silva" "rdp")
#            if [[ " {list[@]} " =~ " {params.collection} " ]]; then
#                kraken-build --special {params.collection} --db {params.db_path}
#            else
#                kraken-build --download-library {params.collection} --db {params.db_path}
#            fi
#
#        """



rule index_centrifuge_db:
    output:
        ex1 = join(config["centrifuge_build_options"]["centrifuge_db"],config["centrifuge_build_options"]["reference_name"]+".1.cf"),
        ex2 = join(config["centrifuge_build_options"]["centrifuge_db"],config["centrifuge_build_options"]["reference_name"]+".2.cf"),
        ex3 = join(config["centrifuge_build_options"]["centrifuge_db"],config["centrifuge_build_options"]["reference_name"]+".3.cf")

    input:
        conv=config["centrifuge_build_options"]["centrifuge_db"]+"/seqid2taxid.map",
        tree=config["centrifuge_build_options"]["centrifuge_db"]+"/taxonomy/nodes.dmp",
        name_table=config["centrifuge_build_options"]["centrifuge_db"]+"/taxonomy/names.dmp",
        fa_path=config["centrifuge_build_options"]["centrifuge_db"]+"/library/"
    params:
        threads=config["centrifuge_build_options"].get("threads","1"),
        reference_name=config["centrifuge_build_options"].get("reference_name","ex")
    #singularity: "singularity_env.sif"
    shell:
        """
        cat {input.fa_path}/*/*.fna |
        centrifuge-build -p {params.threads} --conversion-table {input[conv]} \
                         --taxonomy-tree {input[tree]} --name-table {input[name_table]} \
                          {params[reference_name]}
        """


# Rule: Kraken2 classification_{classifier}
rule kraken2:
    input:
        fastq=in_dir+"/{sample}.fastq",
        kraken_db=config["kraken_options"].get("db","kraken_dbs"),
        hash=config["kraken_options"].get("db","kraken_dbs")+"/hash.k2d",
        opts=config["kraken_options"].get("db","kraken_dbs")+"/opts.k2d",
        taxo=config["kraken_options"].get("db","kraken_dbs")+"/taxo.k2d"
    output:
        krak = join(config["out_dir"], "classification_kraken2/{sample}.kraken"),
        krak_report = join(config["out_dir"], "classification_kraken2/{sample}.kreport")
    #singularity: "singularity_env.sif"
    shell:
        """
           time kraken2 --db {input[kraken_db]} --threads {config[threads]} --output {output.krak} --report {output.krak_report} {input.fastq} --use-names
        """


rule centrifuge:
    input:
        fastq=in_dir+"/{sample}.fastq",
        ex1 = join(config["centrifuge_build_options"]["centrifuge_db"],config["centrifuge_build_options"]["reference_name"]+".1.cf"),
        ex2 = join(config["centrifuge_build_options"]["centrifuge_db"],config["centrifuge_build_options"]["reference_name"]+".2.cf"),
        ex3 = join(config["centrifuge_build_options"]["centrifuge_db"],config["centrifuge_build_options"]["reference_name"]+".3.cf"),
    output:
        report_file=join(config["out_dir"], "classification_centrifuge/{sample}.report"),
        stdout=join(config["out_dir"], "classification_centrifuge/{sample}.centrifuge"),
        kraken_report=join(config["out_dir"],"classification_centrifuge/{sample}.kreport")
    params:
        threads=config["centrifuge_options"].get("threads",1),
        centrifuge_db=join(config["centrifuge_build_options"]["centrifuge_db"],config["centrifuge_build_options"]["reference_name"])
    #singularity: "singularity_env.sif"
    shell:"""
    centrifuge -x {input.centrifuge_db} -S {output.stdout} --report-file {output.report_file} -f {input.fastq} 
    centrifuge-kreport -x {input.centrifuge_db} {output.report_file}  > {output.kraken_report}

    """

rule bracken:
    input:
     krak_report = join(config["out_dir"], "classification_kraken2/{sample}.kreport"),
     krak = join(config["out_dir"], "classification_kraken2/{sample}.kraken")
    output:
     join(config["out_dir"], "classification_{classifier}/{sample}.kreport")
    params:
     kraken_db = config["kraken_options"].get("db", "kraken_dbs"),
     readlen = config["bracken_options"]["read_length"],
     threshold = config["bracken_options"].get("threshold",0),
     level = config["bracken_options"].get("taxonomic_level","S"),
     out = join(config["out_dir"],"classification_{classifier}/{sample}.report"),
     filter=config["bracken_options"].get("filter",0),
     to_=config["bracken_options"]["to"],
     list=config["bracken_options"]["exclude"]

    #singularity: "singularity_env.sif"
    shell: """
       bracken -d {params.kraken_db} -i {input.krak_report} -o {params.out} -w {output} -l {params.level} -t {params.threshold} -r {params.readlen}
       if [ {params.filter} ]; then
         python ./scripts/KrakenTools/filter_bracken.out.py -i {output} -o {output} --{params.to_} {params.list}
        fi
    
        
    """
#rule fix_bracken:
#    input:
#        join(config["out_dir"],"classification_{classifier}/{sample}_bracken.kreport")
#    output:
#        join(config["out_dir"], "classification_{classifier}/{sample}.kreport")
#    shell:
#        """
#        mv {input} {output}
#        """

#Downstream analysis with R
rule combine_kreport:
    input:
        expand(config["out_dir"]+"/classification_{classifier}/{sample}.kreport",sample=SAMPLES.sample,classifier=classifier)
    output:
        config["out_dir"]+f"/classification_{classifier}/combined.kreport"
    shell:
        """
        python ./scripts/KrakenTools/combine_kreports.py -r {input} -o {output} --display-headers
        """

rule kreport2krona:
    input:
        config["out_dir"]+f"/classification_{classifier}"+"/{sample}.kreport"
    output:
        join(config["out_dir"],"krona_results/{sample}.krona")
    shell:
        """
        python ./scripts/KrakenTools/kreport2krona.py -r {input} -o {output}
        """


rule make_biom:
    output:
        join(config["out_dir"],f"analysis/classification_table.biom")
    input:
        expand(config["out_dir"]+f"/classification_{classifier}"+"/{sample}."+f"kreport",sample=SAMPLES.sample, classifier=classifier)

    shell:
        """
        kraken-biom {input} -o {output} --fmt json
        """

rule make_phyloseq:
    input:
       biom_file=join(config["out_dir"],"analysis/classification_table.biom"),
       metadata=config["metadata"]
    output:
        join(config["out_dir"],f"classification_{classifier}"+"/phyloseq_object.rds"),
    #singularity: "docker://Zagh05/MetaLung:metalung"
    params:
        samples=SAMPLES
    script:
        'scripts/make_phyloseq.R'


rule alpha_diversity:
    input:
        phylo_obj=join(config["out_dir"],f"classification_{classifier}"+"/phyloseq_object.rds")
    output:
        join(config["out_dir"], "analysis/alpha_diversity.png")
    params:
        measures = config["alpha_diversity"]["measures"],
        title = config["alpha_diversity"]["title"],
        color = config["alpha_diversity"]["color"],
        xaxis_label = config["alpha_diversity"]["xaxis_label"]
    #singularity: "docker://Zagh05/MetaLung:metalung"
    script:
        'scripts/alpha_diversity.R'

rule beta_diversity:
    input:
        phylo_obj=join(config["out_dir"],f"classification_{classifier}"+"/phyloseq_object.rds")
    output:
        join(config["out_dir"], "analysis/beta_diversity.png")
    params:
        method = config["beta_diversity"]["method"],
        distance = config["beta_diversity"]["distance"],
        title = config["beta_diversity"]["title"],
        color = config["beta_diversity"].get("color",""),
        shape = config["beta_diversity"].get("shape",""),
        type = config["beta_diversity"]["type"],
        wrap = config["beta_diversity"].get("wrap",""),
        label = config["beta_diversity"].get("label",""),
        taxrank = config["beta_diversity"].get("taxrank",""),
        subset = config["beta_diversity"].get("subset",""),
        rank_subset = config["beta_diversity"].get("rank_subset","")


    #singularity: "docker://Zagh05/MetaLung:metalung"
    script:
        'scripts/beta_diversity.R'


rule taxonomic_barplots:
    input:
        phylo_obj=join(config["out_dir"],f"classification_{classifier}"+"/phyloseq_object.rds")
    output:
        join(config["out_dir"],"analysis/taxonomic_barplots.pdf")
    params:
        title = config["taxonomic_barplots"]["title"],
        groups = config["taxonomic_barplots"]["groups"],
        tax_ranks = config["taxonomic_barplots"]["tax_ranks"],
        abundance = config["taxonomic_barplots"]["abundance"],
        abundance_threshold = config["taxonomic_barplots"]["abundance_threshold"],
        label = config["taxonomic_barplots"].get("label",""),
        top_taxa = config["taxonomic_barplots"].get("top_taxa",0)
    #singularity: "docker://Zagh05/MetaLung:metalung"
    script:
        'scripts/taxonomic_barplots.R'

rule lineage_barplots:
    input:
        phylo_obj=join(config["out_dir"],f"classification_{classifier}"+"/phyloseq_object.rds")
    output:
        join(config["out_dir"],"analysis/lineage_barplots.pdf")
    params:
        title = config["lineage_barplots"]["title"],
        groups = config["lineage_barplots"]["groups"],
        abundance = config["lineage_barplots"]["abundance"],
        abundance_threshold = config["lineage_barplots"]["abundance_threshold"],
        lineage = config["lineage_barplots"]["lineage"],
        rank = config["lineage_barplots"]["rank"],
        analysis_rank = config["lineage_barplots"]["analysis_rank"],
        label = config["lineage_barplots"].get("label",""),
        top_taxa = config["taxonomic_barplots"].get("top_taxa",0)
#singularity: "docker://Zagh05/MetaLung:metalung"
    script:
        'scripts/lineage_barplots.R'

rule abund_heatmap:
    input:
        phylo_obj=join(config["out_dir"], f"classification_{classifier}"+"/phyloseq_object.rds")
    output:
        join(config["out_dir"],"analysis/abund_heatmap.png")
    params:
        subset  =   config["abund_heatmap"]["subset"],
        method =   config["abund_heatmap"]["method"],
        distance =   config["abund_heatmap"]["distance"],
        sample_label =  config["abund_heatmap"]["sample_label"],
        taxa_label =   config["abund_heatmap"]["taxa_label"],
        wrap =   config["abund_heatmap"].get("wrap",0)
    #singularity: "docker://Zagh05/MetaLung:metalung"
    script:
        'scripts/abund_heatmap.R'

rule differential_abundance:
    input:
        phylo_obj=join(config["out_dir"],f"classification_{classifier}"+"/phyloseq_object.rds")
    output:
        join(config["out_dir"],"analysis/differential_abundance/"+"compositional_PCA_plot.pdf")

    params:
        subset = config["diff_abund"].get("subset",""),
        groups = config["diff_abund"]["groups"],
        lineage = config["diff_abund"].get("lineage",""),
        lineage_rank = config["diff_abund"].get("rank",""),
        output_dir = join(config["out_dir"],"differential_abundance"),
        top_taxa = join(config["out_dir"],"top_taxa"),
        filter_by_sample = join(config["out_dir"],"filter_by_sample"),
        bh_fdr_cutoff = join(config["out_dir"],"bh_fdr_cutoff"),
        found = join(config["out_dir"],"found"),
        label_significant = join(config["out_dir"],"label_significant"),
        color_significant = join(config["out_dir"],"color_significant")
    #singularity: "docker://Zagh05/MetaLung:metalung"
    script:
        'scripts/differential_abundance.R'