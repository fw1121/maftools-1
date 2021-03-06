#' Extract mutational signatures from trinucletide context.
#'
#' @description Decompose a matrix of 96 substitution classes into \code{n} signatures.
#'
#' @details This function decomposes a non-negative matrix into n signatures.
#' Extracted signatures are compared against 21 experimentally validated signatures by calculating cosine similarity. See http://www.nature.com/nature/journal/v500/n7463/fig_tab/nature12477_F2.html for details. Please be
#' noted that the original study described 21 validated signatures, however cosimc catalogue of cancer signatures has now reached ~30 signatures. Validated signatures
#' lack some of, now well known signatures such Signature-22 (T>A strand bias occuring in liver), and this comparison might not include them. In that case you may have to manually infer the results.
#'
#' @param mat Input matrix of diemnsion nx96 generated by \code{\link{trinucleotideMatrix}}
#' @param n decompose matrix into n signatures. Default NULL. Tries to predict best value for \code{n} by running NMF on a range of values and chooses based on cophenetic correlation coefficient.
#' @param nTry tries upto this number of signatures before choosing best \code{n}. Default 6.
#' @param plotBestFitRes plots consensus heatmap for range of values tried. Default FALSE
#' @param parallel calls to .opt argument of \code{\link{nmf}}. e.g, 'P4' for using 4 cores. See note on \code{\link{nmf}} for MAC users.
#' @return a list with decomposed scaled signatures, signature contributions in each sample and a cosine similarity table against validated signatures.
#' @examples
#' \dontrun{
#' laml.tnm <- trinucleotideMatrix(maf = laml, ref_genome = 'hg19.fa', prefix = 'chr',
#' add = TRUE, useSyn = TRUE)
#' laml.sign <- extractSignatures(mat = laml.tnm, plotBestFitRes = FALSE)
#' }
#' @importFrom NMF nmfEstimateRank nmf basis plot consensusmap coef
#' @importFrom grDevices pdf boxplot.stats dev.off
#' @seealso \code{\link{trinucleotideMatrix}} \code{\link{plotSignatures}}
#' @export


extractSignatures = function(mat, n = NULL, nTry = 6, plotBestFitRes = FALSE, parallel = NULL){

  #suppressPackageStartupMessages(require(NMF, quietly = TRUE))
  #transpose matrix
  mat = t(mat)

  #Validation
  zeroMutClass = names(which(rowSums(mat) == 0))

  if(length(zeroMutClass)){
    message(paste('Warning : Found zero mutations for conversions ', zeroMutClass, sep=''))
    #Add small value to avoid zero counts (maybe not appropriate). This happens when sample size is low or in cancers with low mutation rate.
    mat[which(rowSums(mat) == 0),] = 0.1
  }

  #Notes:
  #Available methods for nmf decompositions are 'brunet', 'lee', 'ls-nmf', 'nsNMF', 'offset'.
  #But based 21 breast cancer signatures data, defualt brunet seems to be working close to the results.
  #Sticking with default for now.

  if(is.null(n)){
    message('Estimating best rank..')
    if(!is.null(parallel)){
      nmfTry = nmfEstimateRank(mat, seq(2,nTry), method='brunet', nrun=10, seed=123456, .opt = parallel) #try nmf for a range of values
    }else{
      nmfTry = nmfEstimateRank(mat, seq(2,nTry), method='brunet', nrun=10, seed=123456) #try nmf for a range of values
    }

    if(plotBestFitRes){
      pdf('nmf_consensus.pdf', bg = 'white', pointsize = 9)
      NMF::consensusmap(nmfTry)
      dev.off()
      message('created nmf_consensus.pdf')
      #print(NMF::plot(nmfTry, 'cophenetic'))
    }

    nmf.sum = summary(nmfTry) # Get summary of estimates
    print(nmf.sum)
    nmf.sum$diff = c(0, diff(nmf.sum$cophenetic))
    bestFit = dplyr::filter(.data = nmf.sum, diff < 0)[1,'rank'] #First point where cophenetic correlation coefficient starts decreasing
    #bestFit = nmf.sum[which(nmf.sum$cophenetic == max(nmf.sum$)),'rank'] #Get the best rank based on highest cophenetic correlation coefficient
    message(paste('Using ',bestFit, ' as a best-fit rank based on decreasing cophenetic correlation coefficient.', sep=''))
    n = bestFit
  }

  if(!is.null(parallel)){
    conv.mat.nmf = NMF::nmf(x = mat, rank = n, .opt = parallel)
  }else{
    conv.mat.nmf = NMF::nmf(x = mat, rank = n)
  }

  #Signatures
  w = NMF::basis(conv.mat.nmf)
  w = apply(w, 2, function(x) x/sum(x)) #Scale the signatures (basis)
  colnames(w) = paste('Signature', 1:ncol(w),sep='_')

  #Contribution
  h = NMF::coef(conv.mat.nmf)
  #For single signature, contribution will be 100% per sample
  if(n == 1){
    h = h/h
    rownames(h) = paste('Signature', '1', sep = '_')
  }else{
    h = apply(h, 2, function(x) x/sum(x)) #Scale contributions (coefs)
    rownames(h) = paste('Signature', 1:nrow(h),sep='_')
  }


  #conv.mat.nmf.signatures.melted = melt(conv.mat.nmf.signatures)
  #levels(conv.mat.nmf.signatures.melted$X1) = colOrder

  sigs = data.table::fread(input = system.file('extdata', 'signatures.txt', package = 'maftools'), stringsAsFactors = FALSE, data.table = FALSE)
  colnames(sigs) = gsub(pattern = ' ', replacement = '_', x = colnames(sigs))
  rownames(sigs) = sigs$Somatic_Mutation_Type
  sigs = sigs[,-c(1:3)]
  sigs = sigs[,1:22] #use only first 21 validated sigantures
  sigs = sigs[rownames(w),]

  message('Comparing against experimentally validated 21 signatures.. (See Alexandrov et.al Nature 2013 for details.)')
  #corMat = c()
  coSineMat = c()
  for(i in 1:ncol(w)){
    sig = w[,i]
    coSineMat = rbind(coSineMat, apply(sigs, 2, function(x){
      crossprod(sig, x)/sqrt(crossprod(x) * crossprod(sig)) #Estimate cosine similarity against all 21 signatures
    }))
    #corMat = rbind(corMat, apply(sigs, 2, function(x) cor.test(x, sig)$estimate[[1]])) #Calulate correlation coeff.
  }
  #rownames(corMat) = colnames(w)
  rownames(coSineMat) = colnames(w)

  # for(i in 1:nrow(corMat)){
  #   message('Found ',rownames(corMat)[i], ' most similar to validated ',names(which(corMat[i,] == max(corMat[i,]))), '. Correlation coeff: ', max(corMat[i,]), sep=' ')
  # }

  for(i in 1:nrow(coSineMat)){
    message('Found ',rownames(coSineMat)[i], ' most similar to validated ',names(which(coSineMat[i,] == max(coSineMat[i,]))), '. CoSine-Similarity: ', max(coSineMat[i,]), sep=' ')
  }

  return(list(signatures = w, contributions = h, coSineSimMat = coSineMat, nmfObj = conv.mat.nmf))
}
