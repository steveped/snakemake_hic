rule get_maxhic:
    output:
        exe = "scripts/MaxHiC/Main.py",
        general = directory("scripts/MaxHiC/General"),
        capture = directory("scripts/MaxHiC/Capture")
    threads: 1
    shell:
        """
        wget https://github.com/Rassa-Gvm/MaxHiC/archive/master.zip
        unzip master.zip -d MaxHiC
        mv MaxHiC/MaxHiC-master scripts/MaxHiC
        rm master.zip
        rmdir MaxHiC
        rm -rf scripts/MaxHiC/Sample_Inputs
        """

rule run_maxhic:
    input:
        maxhic_exe = ancient(rules.get_maxhic.output.exe),
        mat = os.path.join(
            hic_data_path,
            "hic_results", "matrix", "merged", "raw", "{bin}",
            "merged_" + "{bin}" + ".matrix"
        ),
        bed = os.path.join(
            hic_data_path,
            "hic_results", "matrix", "merged", "raw", "{bin}",
            "merged_" + "{bin}" + "_abs.bed"
        )
    output:
        cis = "output/MaxHiC/merged/{bin}/cis_interactions.txt.gz",
        trans = "output/MaxHiC/merged/{bin}/trans_interactions.txt.gz",
        model_params = directory("output/MaxHiC/merged/{bin}/ModelParameters")
    params:
        input_path = os.path.join(
            hic_data_path,
            "hic_results", "matrix", "merged", "raw", "{bin}"
        ),
        output_path = os.path.join(
            "output", "MaxHiC", "merged", "{bin}"
        )
    conda: "../envs/maxhic.yml"
    log: "logs/MaxHiC/merged_{bin}_MaxHiC.log"
    threads: 16
    shell:
        """
        ## Given the problems with the raw output from HiC-Pro, we should
        ## delete any *ord.bed* files that exist. They seem to have been 
        ## excluded from HiC-Pro v3
        if compgen -G "{params.input_path}/*ord.bed" > /dev/null; then
          echo -e "Deleting unnecessary symlink"
          rm {params.input_path}/*ord.bed
        fi

        python {input.maxhic_exe} \
          -t {threads} \
          {params.input_path} \
          {params.output_path} &> {log}

        ## Compress the output files
        gzip {params.output_path}/*txt
        """