#!/usr/bin/env nextflow

params.metadata = "datalist.txt"
params.datadir  = null
params.outdir   = "bc-results"

// awesome comment


Channel.fromPath(params.metadata)
  .flatMap{ it.readLines() }
  .view()
  .set { ch_datalist }


process get_datasets {

    tag "$datasetname"

    input:
    val datasetname from ch_datalist

    output:
    set val(datasetname), file('*.h5ad') into ch_bbknn, ch_scanorama
    set val(datasetname), file('*.rds') into  ch_R_limma, ch_R_combat

    shell:
    '''
    pyfile="!{params.datadir}/!{datasetname}.h5ad"
    Rfile="!{params.datadir}/!{datasetname}.rds"
    if [[ ! -e $pyfile || ! -e $Rfile ]]; then
      echo "Please check existence of $pyfile and $Rfile"
      false
    fi
    ln -s $pyfile .
    ln -s $Rfile .
    '''
}


process py_bbknn {

    tag "bbknn (py) $datasetname"

    input:
    set val(datasetname), file(datain) from ch_bbknn

    output:
    set val(datasetname), val('bbknn'), file('bbknn.*.h5ad') into ch_bbknn_entropy

    shell:
    '''
    bbknn_script.py !{datain} bbknn.!{datasetname}.h5ad
    '''
}

process py_scanorama{
	tag "scanorama (py) $datasetname"

	input:
	set val(datasetname), file(datain) from ch_scanorama
	
	output:
	set val(datasetname), val('scanorama'), file('scanorama.*.h5ad') into ch_scan_entropy
	
	shell:
	'''
	scanorama_script.py !{datain} scanorama.!{datasetname}.h5ad
	'''
}


ch_bbknn_entropy.mix(ch_scan_entropy).set{ch_py_entropy}


process R_limma{

	tag "limma (R) $datasetname"
	
	input: 
	set val(datasetname), file(datain) from ch_R_limma

	output:
	set val(datasetname), val('limma'), file('limma.*.rds') into ch_R_limma_entropy

	shell:
	'''
	limma_script.R !{datain} limma.!{datasetname}.rds
	'''
}

process R_combat{
	
	tag "combat (R) $datasetname"

	input:
	set val(datasetname), file(datain) from ch_R_combat

	output:
	set val(datasetname), val('ComBat'), file('ComBat.*.rds') into ch_R_ComBat_entropy
	
	shell:
	'''
	combat_script.R !{datain} ComBat.!{datasetname}.rds
	'''
}

ch_R_limma_entropy.mix(ch_R_ComBat_entropy).set{ch_R_entropy}

process R_entropy {

    tag "entropy (R) $datain $method $datasetname"

    publishDir "${params.outdir}", mode: 'copy'

    input:
    set val(datasetname), val(method), file(datain) from ch_R_entropy

    output:
    file('*.epy')

    shell:
    '''
    entropy_scripts/entropy_script_R.R !{datain} exp_mat !{method}.!{datasetname}.epy
    '''
}

process py_entropy {

    tag "entropy (python) $datain $method $datasetname"

    publishDir "${params.outdir}", mode: 'copy'

    input:
    set val(datasetname), val(method), file(datain) from ch_py_entropy

    output:
    file('*.epy')

    shell:
    '''
    entropy_scripts/entropy_script.py !{datain}  !{method}.!{datasetname}.epy
    '''
}





