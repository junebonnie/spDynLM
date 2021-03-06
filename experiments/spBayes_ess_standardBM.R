#-----------------------------------------------------------------------------
# This program use the standard batch means (BM) calculation in the relative
# standard deviation fixed-width stopping rule.
#
# The effective sample size(ESS) as stopping criterion with tunable parameters
# (n.ess) is implemented to terminate the MCMC simulation from the spDynLM()
# from the R package "spBayes". The evaluation of the performance is carried 
# out by comparing to the "truth" from truth.txt.
#
# input
# ------
# args: a unique integer (e.g. i) indicates that it is the i-th run. Check 
# the spBayes_ess_standardBM.sh file for more details.
#
# output
# -------
# "$n.ess"_args[1]_cond_ess_standard.txt: 
#
# "$n.ess"_args[1]_output_ess_standard.txt: matrix of parameter-wise total 
# simulation effort, standard effective sample size and proposed effective 
# sample size.
#
# "$n.ess"_args[1]_mcse_ess_standard.txt: sequence of parameter-wise markov
# chain standard error.
#
# "$n.ess"_args[1]_sd_ess_standard.txt: sequence of parameter-wise posterior 
# standard deivation.
#
# "$n.ess"_args[1]_mean_ess_standard.txt: sequence of parameter-wise posterior
# mean.
#
# “$n.ess”_args[1]_time_ess_standard.txt: record the actual run time.
#
# "$n.ess"_args[1]_probcover_ess_standard.txt: 0/1 valued sequence used to 
# estimate the coverage probabilities of each parameter.
#
# "$n.ess"_args[1]_probdist_ess_standard.txt: 0/1 valued sequence used to 
# estimate the prob. of whether the distance of estimates from truth is larger
# than the threshold.
#-----------------------------------------------------------------------------

require(mcmcse)
require(spBayes)

#### set random seed ####
args<-commandArgs(TRUE)
set.seed(args[1])

#### record present time ####
# ptm<- proc.time()

#### spatial Bayesian model setup ####
## manipulate raw data
data("NETemp.dat")
ne.temp <- NETemp.dat
ne.temp <- ne.temp[ne.temp[,"UTMX"] > 5500000 & ne.temp[,"UTMY"] > 3250000,]
y.t <- ne.temp[,4:15]
N.t <- ncol(y.t) ##number of months
n <- nrow(y.t) ##number of observation per months
## scale to km
coords <- as.matrix(ne.temp[,c("UTMX", "UTMY")]/1000)
max.d <- max(iDist(coords))
## set starting and priors
p <- 2 #number of regression parameters in each month
starting <- list("beta"=rep(0,N.t*p), "phi"=rep(3/(0.5*max.d), N.t),
                 "sigma.sq"=rep(2,N.t), "tau.sq"=rep(1, N.t),
                 "sigma.eta"=diag(rep(0.01, p)))
tuning <- list("phi"=rep(5, N.t))
priors <- list("beta.0.Norm"=list(rep(0,p), diag(1000,p)),
               "phi.Unif"=list(rep(3/(0.9*max.d), N.t), 
                               rep(3/(0.05*max.d), N.t)),
               "sigma.sq.IG"=list(rep(2,N.t), rep(10,N.t)),
               "tau.sq.IG"=list(rep(2,N.t), rep(5,N.t)),
               "sigma.eta.IW"=list(2, diag(0.001,p)))
##make symbolic model formula statement for each month
mods <- lapply(paste(colnames(y.t),'elev',sep='~'), as.formula)

#### generate MCMC samples ####
n.samples<- 500000
#n.samples<- 2000000
m.1 <- spDynLM(mods, data=cbind(y.t,ne.temp[,"elev",drop=FALSE]), 
               coords=coords,starting=starting, tuning=tuning, priors=priors,
               get.fitted =TRUE,cov.model="exponential", n.samples=n.samples,
               n.report=0.1*n.samples)
samples<- cbind(m.1$p.beta.0.samples, m.1$p.beta.samples, 
                m.1$p.sigma.eta.samples, m.1$p.theta.samples,
                t(m.1$p.u.samples))
rm(m.1)

#### record present time ####
ptm<- proc.time()

#### apply stopping rule (relative FWSR) retrospectively ####
bm<- function(x){
  n= length(x)
  b= floor(sqrt(n))
  a= floor(n/b)
  
  y = sapply(1:a, function(k) return(mean(x[((k - 1) * b + 1):(k * b)])))
  mu.hat = mean(y)
  var.hat = b * sum((y - mu.hat)^2)/(a - 1)
  se = sqrt(var.hat/n)
  return(se)
}

n.ess<- 1000
#n.ess<- 5000
jump<- 20
check<- 2^14
z<- 1.96
eps<- sqrt(4*1.96^2/n.ess)
while(1){
  # print(check)
  mcse<- apply(samples[0:check,], 2, bm)
  std<- apply(samples[0:check,], 2, sd)
  ess.standard<- (std/mcse)^2
  write.table(ess.standard, paste(n.ess, "cond_ess_standard.txt", sep="_"))
  if(all(ess.standard>=n.ess)){
    ess.old<- apply(samples[0:check,], 2, ess)
    ess.app<- 4*(z/eps)^2
    X.mean<- apply(samples[0:check,], 2, mean)
    out<- list(n= check, app= ess.app, old= ess.old, new= ess.standard)
    write.table(out, paste(n.ess, args[1],"output_ess_standard.txt",sep="_"),
                row.names=FALSE)
    write.table(mcse, paste(n.ess, args[1], "mcse_ess_standard.txt", sep="_"),
                row.names=FALSE)
    write.table(std, paste(n.ess, args[1], "sd_ess_standard.txt", sep="_"),
                row.names=FALSE)
    write.table(X.mean, paste(n.ess, args[1],"mean_ess_standard.txt",sep="_"),
                row.names=FALSE)
    break
  }
  
  b.size<- floor(sqrt(check))
  check<- check+jump*b.size
  nbatch<- floor(check/b.size)
  if(!(nbatch%%2)){check<- check+b.size}
}

#### run time ####
write((proc.time()-ptm)[1:3], paste(n.ess, args[1], 
                                    "time_ess_standard.txt", sep="_"))

#### check coverage probability ####
truth<- read.table("truth.txt", header = TRUE)
upper<- X.mean+z*mcse
lower<- X.mean-z*mcse
# coverage of the resulting confidence interval (0/1)
prob.coverage<- matrix((truth[,1]>=lower)&(truth[,1]<=upper), ncol=1)*1
write.table(prob.coverage, 
            paste(n.ess, args[1], "probcover_ess_standard.txt", sep="_"),
            row.names=FALSE)
# distance between estimates and truth
prob.distance<- matrix(abs(X.mean-truth[,1])>=eps*truth[,2], ncol=1)*1
write.table(prob.distance, 
            paste(n.ess, args[1], "probdist_ess_standard.txt", sep="_"), 
            row.names=FALSE)





