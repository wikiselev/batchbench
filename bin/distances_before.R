#!/usr/bin/env Rscript

#This script is for the calculation of the cosine distances of the datasets prior to batch correction.
#As some methods correct the PCA space and others the count matrix, distance over both spaces are calculated.

#libraries
library(scran)
library(SingleCellExperiment)
library(lsa)

#arguments
args <- R.utils::commandArgs(asValues=TRUE)
if (is.null(args[["input"]])) {
  print("Provide a valid input file name (Batch corrected object) --> RDS file")
}
if (is.null(args[["output"]])) {
  print("Provide a valid output file name (Per batch and cell type entropy) --> CSV file")
}

#input file
object <- readRDS("~/RubenChG/trial_objects/mini_pancreas.rds")

#remove those batch / cell types present less than X_threshold times
remove_elements <- function (object, filter_vec, threshold, info){
  removal_names <- names(table(filter_vec)[table(filter_vec) <= threshold])
  if (length(removal_names) == 0) print(paste("There is no", info, "with less than", threshold, "cells"))
  if (length(removal_names) != 0){
    print(paste("There are", length(removal_names), info,  "with less than", threshold, "cells :", paste(removal_names, collapse = ", "), "removed!"))
    for(i in 1:length(removal_names)){
      object <- object[, object$Batch != removal_names[[i]]]
      object <- object[, object$cell_type1 != removal_names[[i]]]
    }
  }
  return(object)
}

#remove those batch / cell types present less than X_threshold times from Seurat object.
#My goal is to unify these 2 functions into 1 but at the moment I'm busy!
remove_elements_seurat <- function (object, filter_vec, threshold, info){
  removal_names <- names(table(filter_vec)[table(filter_vec) <= threshold])
  if (length(removal_names) == 0) print(paste("There is no", info, "with less than", threshold, "cells"))
  if (length(removal_names) != 0){
    print(paste("There are", length(removal_names), info,  "with less than", threshold, "cells :", paste(removal_names, collapse = ", "), "removed!"))
    for(i in 1:length(removal_names)){
      object <- SubsetData(object, cells.use = object@meta.data[["Batch"]] != removal_names[[i]])
      object <- SubsetData(object, cells.use = object@meta.data[["cell_type1"]] != removal_names[[i]])
    }
  }
  return(object)
}

#subset space by batch and by cell type
subset_space <- function(space, b_vector, N_b){
  colnames(space) <- b_vector
  subset_list <- lapply(1:N_b, function(x) {space[, colnames(space) == names(table(b_vector)[x])]}) #careful with comma!
  return(subset_list)
}
#compute similarity. This function returns a list of cosine similarity symmetric matrices.
compute_similarity <- function(subset_list){
  sim_list <- list()
  for (i in 1: length(subset_list)){
    sim_list[[i]] <- cosine(x = subset_list[[i]])
  }
  return(sim_list)
}
#extract values from symmetric matrices
extract_values <- function(sim_list){
  vals <- list()
  for(n in 1: length(sim_list)){
    vals[[n]] <-  c(sim_list[[n]][lower.tri(sim_list[[n]], diag = FALSE)])
  }
  return(vals)
}

#save results function
save_results <- function(x){
  write.table(x, file = args[["output"]], sep = "\t", row.names = FALSE)
}


#arguments for similarity calculation
batch_vector <- as.character(object$Batch)
#remove from  vector those cell types with less than threshold times 
batch_threshold <- 10
object <- remove_elements(object, filter_vec = batch_vector, threshold = batch_threshold, info = "batch/es")

if ("cell_type1" %in% colnames(colData(object))){
  print("The object has cell type annotation")
  cell_type_vector <- as.character(object$cell_type1)
  #remove from  vector those cell types with less than threshold times 
  cell_type_threshold = 1
  object <- remove_elements(object, filter_vec = cell_type_vector, threshold = cell_type_threshold, info = "cell type/s")
}

#redifine vectors after filtering
batch_vector <- as.character(object$Batch)
N_batches <- length(unique(batch_vector))
cell_type_vector <- as.character(object$cell_type1)
N_cell_types <- length(unique(cell_type_vector))

#1.1) Distance over PCA graph
library(scater)
object <- runPCA(object, ncomponents = 10, method = "prcomp", exprs_values = "logcounts")

space <- object@reducedDims@listData[["PCA"]]

space <- t(space) #We transpose to avoid code duplication, as pca_graph is cells x PCs and exp_matrix is genes x cells. 
similarity_batch_list <- compute_similarity(subset_list = subset_space(space = space, b_vector = batch_vector, N_b = N_batches))
similarity_cell_type_list <- compute_similarity(subset_list = subset_space(space = space, b_vector = cell_type_vector, N_b = N_cell_types))
pca_similarity_list <- append(similarity_batch_list, similarity_cell_type_list)

#1.2) Distance over counts matrix
space <- assay(object, "logcounts")

similarity_batch_list <- compute_similarity(subset_list = subset_space(space = space, b_vector = batch_vector, N_b = N_batches))
similarity_cell_type_list <- compute_similarity(subset_list = subset_space(space = space, b_vector = cell_type_vector, N_b = N_cell_types))
counts_similarity_list <- append(similarity_batch_list, similarity_cell_type_list)

#append both lists
general_list <- append(pca_similarity_list,counts_similarity_list)
#extract values from matricesz
values_list <- extract_values(general_list)

#convert list of lists to dataframe
values_df <- as.data.frame(t(plyr::ldply(values_list, rbind, .id = NULL)))
#name dataframe
colnames(values_df) <- c(paste0("bef_correct_PCA_dist_BATCH", names(table(batch_vector))), 
                         paste0("bef_correct_PCA_dist_CELL", names(table(cell_type_vector))), 
                         paste0("bef_correct_Counts_dist_BATCH", names(table(batch_vector))),
                         paste0("bef_correct_Counts_dist_CELL", names(table(cell_type_vector))))
                         
print(summary(values_df))
print("Distances over the Pca graph, and counts matrix (prior to batch correction) succesful!")
#save results
save_results(values_df)

