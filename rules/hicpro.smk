rule find_rs_fragments:
    input: rules.unzip_reference.output
    output:
        rs = rs_frags
    params:
        restriction_site = config['hicpro']['restriction_site'],
        script = os.path.join(
          os.path.dirname(hic_path), 
          "utils", 
          "digest_genome.py"
        )
    threads: 1
    conda: "../envs/hicpro.yml"
    shell:
        """
        # Run the python script
        python {params.script} \
          -r {params.restriction_site} \
          -o {output.rs} \
          {input}
        """

rule make_hicpro_config:
    input:
        idx = os.path.dirname(rules.bowtie2_index.output[0]),
        rs = rs_frags,
        chr_sizes = chr_sizes
    output:
        hicpro_config
    params:
        template = os.path.join(
          os.path.dirname(
            os.path.dirname(hic_path)
          ), 
          "config-hicpro.txt"
        )
    conda: "../envs/stringr.yml"
    threads: 1
    shell:
        """
        Rscript --vanilla \
          scripts/write_hicpro_config.R \
          {input.idx} \
          {input.chr_sizes} \
          {input.rs} \
          {params.template} \
          {output}
        """

rule hicpro_mapping:
    input:
        config = hicpro_config,
        files = expand(
          [trim_path + "/{sample_path}{read_ext}{suffix}"],
          sample_path = df['path'],
          read_ext = read_ext,
          suffix = suffix
        )
    output:
        bwt2 = temp(
            expand(
                ["{path}/{sample_path}{reads}_" + build + "." + assembly + "{suffix}"],
                path = os.path.join(bowtie_data_path, "bwt2"),
                sample_path = df['path'],
                reads = read_ext,
                suffix = ['.bwt2merged.bam', '.mapstat']
            )
        ),
        bwt2_global = temp(
          expand(
            ["{path}/{sample_path}{reads}_{meta}.{suffix}"],
            path = os.path.join(bowtie_data_path, "bwt2_global"),
            sample_path = df['path'],
            reads = read_ext,
            meta = build + "." + assembly + ".bwt2glob",
            suffix = ['bam', 'unmap.fastq']
          )
        ),
        bwt2_local = temp(
          expand(
            ["{path}/{sample_path}{reads}_{meta}_{suffix}"],
            path = os.path.join(bowtie_data_path, "bwt2_local"),
            sample_path = df['path'],
            reads = read_ext,
            meta = build + "." + assembly + ".bwt2glob.unmap",
            suffix = ['bwt2loc.bam', 'trimmed.fastq']
          )
        )
    params:
        outdir = hic_data_path,
        indir = trim_path
    threads: config['hicpro']['ncpu']
    conda: "../envs/hicpro.yml"
    shell:
        """
        ## Remove any existing data as leaving this here causes HicPro to
        ## make an interactive request. Piping `yes` into HicPro may be the
        ## source of some current problems
        if [[ -d {params.outdir} ]]; then
          rm -rf {params.outdir}
        fi

        ## Run HiC-pro
        HiC-Pro \
          -s mapping \
          -c {input.config} \
          -i {params.indir} \
          -o {params.outdir} 
        """

rule hicpro_qc:
    input:
        config = hicpro_config,
        bwt2 = expand(
                ["{path}/{sample_path}{reads}_" + build + "." + assembly + "{suffix}"],
                path = os.path.join(bowtie_data_path, "bwt2"),
                sample_path = df['path'],
                reads = read_ext,
                suffix = ['.bwt2merged.bam', '.mapstat']
            )
    output:
        expand(
          [hic_data_path + "/hic_results/pic/{sample}/plotMapping_{sample}.pdf"],
          sample = samples
        )
    params:
        indir = os.path.join(bowtie_data_path, "bwt2"),
        outdir = hic_data_path
    threads: 1
    conda: "../envs/hicpro.yml"
    shell:
        """
        HiC-Pro \
          -s quality_checks \
          -c {input.config} \
          -i {params.indir} \
          -o {params.outdir} 
        """
        
rule hicpro_proc:
    input:
        config = hicpro_config,
        bwt2 = expand(
                ["{path}/{sample_path}{reads}_" + build + "." + assembly + "{suffix}"],
                path = os.path.join(bowtie_data_path, "bwt2"),
                sample_path = df['path'],
                reads = read_ext,
                suffix = ['.bwt2merged.bam', '.mapstat']
            )
    output:
        bam = temp(
          expand(
            [bowtie_data_path + "/bwt2/{sample_path}_{meta}.{suffix}"],
            meta = build + "." + assembly + ".bwt2pairs",
            suffix = ['bam', 'pairstat'],
            sample_path = df['path']
          )
        ),
        pairs = temp(
           expand(
             [hic_data_path + "/hic_results/data/{sample_path}_{meta}.{suffix}"],
             meta = build + "." + assembly + ".bwt2pairs",
             suffix = ['DEPairs', 'DumpPairs', 'FiltPairs', 'REPairs', 'RSstat', 'SCPairs', 'singlePairs', 'validPairs'],
             sample_path = df['path']
             )
        )
    params:
        indir = os.path.join(bowtie_data_path, "bwt2"),
        outdir = hic_data_path
    threads: config['hicpro']['ncpu']
    conda: "../envs/hicpro.yml"
    shell:
        """
        HiC-Pro \
          -s proc_hic \
          -c {input.config} \
          -i {params.indir} \
          -o {params.outdir} 
        """

# rule hicpro_merge:
#     input:
#         config = hicpro_config,
#         files = hic_data_path + "/hic_results/data/{sample}/{sample}_" + build + "." + assembly + ".bwt2pairs.validPairs"
#     output:
#         pairs = hic_data_path + "/hic_results/data/{sample}/{sample}_allValidPairs",
#         stat = hic_data_path + "/hic_results/data/{sample}/{sample}_allValidPairs.mergestat",
#     params:
#         indir = hic_data_path + "/hic_results/data",
#         outdir = hic_data_path
#     log: "logs/hicpro/hicpro_merge_{sample}.log"
#     threads: config['hicpro']['ncpu']
#     shell:
#         """
#         ######################################
#         ## Specific to phoenix for now only ##
#         ######################################
#         ## Load modules
#         module load HiC-Pro/2.9.0-foss-2016b

#         ##Run HiC-pro responding to yes to any interactive requests
#         HiC-Pro \
#           -s merge_persample \
#           -c {input.config} \
#           -i {params.indir} \
#           -o {params.outdir} &> {log}
#         """

# rule build_contact_maps:
#     input:
#         config = hicpro_config,
#         pairs = hic_data_path + "/hic_results/data/{sample}/{sample}_allValidPairs"
#     output:
#         bed = expand([hic_data_path + "/hic_results/matrix/{{sample}}/raw/{bin}/{{sample}}_{bin}_abs.bed"],
#                      bin = bins),
#         mat = expand([hic_data_path + "/hic_results/matrix/{{sample}}/raw/{bin}/{{sample}}_{bin}.matrix"],
#                      bin = bins)
#     params:
#         indir = hic_data_path + "/hic_results/data",
#         outdir = hic_data_path
#     log: "logs/hicpro/build_contact_maps_{sample}.log"
#     threads: config['hicpro']['ncpu']
#     shell:
#         """
#         ######################################
#         ## Specific to phoenix for now only ##
#         ######################################
#         ## Load modules
#         module load HiC-Pro/2.9.0-foss-2016b

#         ##Run HiC-pro responding to yes to any interactive requests
#         HiC-Pro \
#           -s build_contact_maps \
#           -c {input.config} \
#           -i {params.indir} \
#           -o {params.outdir} &> {log}
#         """
