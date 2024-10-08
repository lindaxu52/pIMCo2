#' Intermodal Coupling with PCA
#'
#' @param files list of antsImages
#' @param nhoods from antsGetNeighborhood in mask
#' @param nhood_weights from get_weights
#' @param mask_indices indices at which mask value is 1
#' @param verbose TRUE or FALSE
#' @param prop_miss proportion of voxels in a neighborhood allowed to be missing
#' @param pca_type "global_wcov" or "unscaled_wcor"
#' @param use_ratio default FALSE for (logit of 1st eigenvalue scaled to 0-1), TRUE for (1st eigenvalue/total variance)
#'
#' @return antsImage with coupling values
#' @noRd
#'
#' @importFrom rlist list.rbind
#' @importFrom stats cov.wt
#' @importFrom ANTsRCore antsImageWrite
imco_pca <- function(files,
                     nhoods,
                     nhood_weights,
                     mask_indices,
                     verbose = TRUE,
                     prop_miss = NULL,
                     pca_type = NULL,
                     use_ratio = FALSE) {
  # Restructure to get eigen decomp at each voxel
  # Takes nhoods (from imco.R, which uses ANTsR::getNeighborhoodInMask (https://rdrr.io/github/ANTsX/ANTsR/man/getNeighborhoodInMask.html) -  
  # turns scalar image into matrix with rows of center voxels with listed neighbors 
  imgVals <- lapply(nhoods, function(x) x$values)
  bigDf <- rlist::list.rbind(imgVals)
  matList <- lapply(split(bigDf, col(bigDf)),
                    function(x) matrix(x, ncol = length(files)))
  rmnaList <- lapply(matList, function(x) {
    w <- nhood_weights
    xRows <- apply(as.matrix(x), 1, function(z) {
      !any(is.na(z))
    })
    if (sum(xRows) > 2) {
      # If the proportion of missing voxels is greater than prop_miss, return NA
      if (mean(!xRows) > prop_miss) {
        return(NA)
      } else {
        return(cbind(w[xRows], as.matrix(x)[xRows, ]))
      }
    }
    return(NA)
  })
  rm(bigDf, matList, imgVals, nhoods)

  if (verbose) {
    cat("# Computing weighted covariances \n")
  }
  rmnaListCenter <- lapply(rmnaList, function(x) {
    if (!is.na(x)[1]) {
      w <- x[, 1]
      newx <- scale(x[, -1], center = TRUE, scale = FALSE)
      return(cbind(w, newx))
    }
    return(NA)
  })
  rm(rmnaList)
  # Weighted cov of each matrix in matList
  if (pca_type == "global_wcov") {
    wcovList <- lapply(rmnaListCenter, function(x) {
      if (!is.na(x)[1]) {
        w <- x[, 1]
        newx <- x[, -1]
        return(stats::cov.wt(newx, wt = w, center = FALSE)$cov)
      }
      return(NA)
    })
  }
  if (pca_type == "unscaled_wcor") {
    wcovList <- lapply(rmnaListCenter, function(x) {
      if (!is.na(x)[1]) {
        w <- x[, 1]
        newx <- x[, -1]
        # return(stats::cov.wt(newx, wt = w, center = FALSE, cor = T)$cor)
        return(stats::cov.wt(newx, wt = w, center = FALSE, cor = T)$cor[2])
      }
      return(NA)
    })
  }
  cat(paste(wcovList))

  # at brain edges, if all voxels in neighborhood in one modality are 0, coupling shouldn't be calculated
  count_na <- 0
  wcovList_corrected <- vector(mode = "list", length = length(wcovList))
  for (i in 1:length(wcovList)) {
    current <- wcovList[[i]]
    if (any(is.na(current) | current == 0)) {
      current <- NA
      count_na <- count_na + 1
    }
    wcovList_corrected[[i]] <- current
  }
  rm(wcovList, rmnaListCenter)

  if (verbose) {
    cat(paste("# Coupling coefficient was not calculated for", count_na, "voxels \n"))
  }

  correlationmatrix <- vector(mode = "list", length = length(wcovList_corrected))
  for (i in 1:length(wcovList_corrected)) {
    current2 <- wcovList_corrected[[i]]
    correlation <- current2[2]
    correlationmatrix[[i]] <- correlation
    if (i == 1) {
      cat(paste(current2))
      cat(paste(correlation))
      }
  }
                    
  # Compute eigenvectors and eigenvalues of covariance matrix to identify principal components
  # if (verbose) {
  #   cat("# Computing weighted PCs \n")
  # }

  # eigen_list <- lapply(wcovList_corrected, function(x) {
  #   if (!is.na(x)[1]) {
  #     return(eigen(x))
  #   } else {
  #     return(NA)
  #   }
  # })

  # rm(wcovList_corrected)

  if (verbose) {
    cat("# Extracting IMCo images \n")
  }

  # if (!use_ratio) {
  #   coupling_vec <- lapply(eigen_list, function(eigen_mat) {
  #     if (!is.na(eigen_mat)[1]) {
  #       dim <- length(eigen_mat$values)
  #       scaled <- (dim / (dim - 1)) * eigen_mat$values[1] / sum(eigen_mat$values) - (1 / (dim - 1)) #scales possible values to min = 0, max = 1
  #       logit <- log(scaled) - log(1 - scaled)
  #       return(logit)
  #     }
  #     else {
  #       return(NA)
  #     }
  #   })
  #   coupling_vec <- as.vector(unlist(coupling_vec))
  # } else if (use_ratio) {
  #   coupling_vec <- lapply(eigen_list, function(eigen_mat) { #true ratio
  #     if (!is.na(eigen_mat)[1]) {
  #       eigen_mat$values[1] / sum(eigen_mat$values)
  #     }
  #     else {
  #       return(NA)
  #     }
  #   })
  #   coupling_vec <- as.vector(unlist(coupling_vec))
  # }

  # coupling_vec <- lapply(eigen_list, function(eigen_mat) { # true ratio
  #   if (!is.na(eigen_mat)[1]) {
  #     eigen_mat$values[1] / sum(eigen_mat$values)
  #   }
  #   else {
  #     return(NA)
  #   }
  # })
  # coupling_vec <- as.vector(unlist(coupling_vec))
  correlation_vec <- as.vector(unlist(correlationmatrix))
                    
  #if (!use_ratio) {
  #  dim <- length(files)
  #  dim_rat <- dim / (dim - 1)
  #  coupling_vec <- (coupling_vec - (1 / dim)) * dim_rat
  #  coupling_vec <- log(coupling_vec) - log(1 - coupling_vec)
  #}

  coupling <- make_ants_image(vec = correlation_vec, mask_indices = mask_indices, reference = files[[1]])

  return(coupling)
}
