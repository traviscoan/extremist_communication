# Script to estimate classification error model used in Baele, Boyd, and Coan (2018)

library(rethinking) # we use logistic() and extract.samples() from this package
library(rstan)
rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores())
library(dummies)
library(plyr)
library(coda)
options(scipen=999)

# Change to data directory
setwd('CHANGE TO DATA DIRECTORY')

# ----------------------------------------------------------------------------------
# Helper functions

logit <- function(p){
  # Return logit scale value for a probability
  return(-log((1/p)-1))
}

log.odds <- function(p, alpha){
  # Return log odds based on a given probability
  return(-alpha + logit(p))
}

# Estimate the mean hyperparameters for coefficients
# using a normal prior
get.normal.hyper <- function(x, time_id){
  # Takes the variable of interest (x) and a 
  # time ID variable (time_id) and returns
  # the "mu" hyperparameter for a normal prior 
  # on a log-odds scale.
  
  # Get priors based on estimated proportions:
  p_hat = tapply(x, time_id, mean)
  
  # Convert to log-odds
  alpha = logit(p_hat[1])
  p_hat = p_hat[2:length(p_hat)] # remove intercept
  
  coeff = vector(length = length(p_hat))
  for (i in seq(length(p_hat))){
    coeff[i] = log.odds(p_hat[i], alpha)
  }
  return(list(alpha = alpha,
              coeff = coeff))
}

# Simple lookup for beta priors
get.beta.hyper <- function(vname){
  hypers = list(
    ingroup = list(eta = c(18, 2), theta = c(19, 1)),
    outgroup = list(eta = c(15, 1), theta = c(23, 1)),
    solution = list(eta = c(12, 1), theta = c(22, 5)),
    crisis = list(eta = c(6, 1), theta = c(31, 2)),
    jihad = list(eta = c(8, 2), theta = c(25, 5)),
    utopia = list(eta = c(1, 1), theta = c(3, 2)),
    punish = list(eta = c(1, 1), theta = c(3, 2)),
    unity = list(eta = c(1, 1), theta = c(3, 2)),
    outplot = list(eta = c(5, 1), theta = c(33, 1)),
    sinful = list(eta = c(1, 1), theta = c(3, 2)),
    victim = list(eta = c(1, 1), theta = c(3, 2)),
    occupy = list(eta = c(1, 1), theta = c(3, 2))
  )
  
  return(hypers[vname])
}

# Get predicted probability for time periods
# Function to return probability based on estimated
# coefficients, eta, and theta.
get.prob <- function(x, idx, intercept = F){
  if (intercept == T) {
    p = logistic(x[idx[1]])[[1]]
    # For intercept, length(idx) = 3
    p_adj = x[idx[2]]*p + (1-x[idx[3]])*(1-p)
  }
  else {
    p = logistic(x[idx[1]] + x[idx[2]])[[1]]
    # For coeffs, length(idx) = 4
    p_adj = x[idx[3]]*p + (1-x[idx[4]])*(1-p)
  }
  return(p_adj)
}

# Function to initialize data prior to getting
# probabilities
init.prob <- function(coeffs, post){
  # Preallocate results matrix
  probs = matrix(nrow = length(coeffs) + 1, ncol = 3)
  
  # Get estimates for the intercept
  idx = c(which(colnames(post) == "a"),
          which(colnames(post) == "eta"), 
          which(colnames(post) == "theta"))
  a = apply(post, 1, get.prob, idx = idx, intercept = T)
  ests = quantile(a, probs = c(.025, .5, 0.975))
  probs[1,] = ests
  
  for (i in seq(length(coeffs))){
    # Get variable positions
    idx = c(which(colnames(post) == "a"),
            which(colnames(post) == coeffs[i]),
            which(colnames(post) == "eta"), 
            which(colnames(post) == "theta"))
    
    # Convert to probabilities
    b = apply(post, 1, get.prob, idx = idx)
    ests = quantile(b, probs = c(.05, .5, 0.95))
    probs[i+1,] = ests
  }
  
  return(probs)
}

get.oneparm.prior = function(x, x_name){
  # Get prior mean for alpha
  p_hat = mean(x)
  
  # Convert to log-odds
  alpha = logit(p_hat)
  
  # Get beta hypers
  bhyper = get.beta.hyper(x_name)
  alpha_sens = bhyper[[1]]$eta[1]
  beta_sens = bhyper[[1]]$eta[2]
  alpha_spec = bhyper[[1]]$theta[1]
  beta_spec = bhyper[[1]]$theta[2]
  
  return(c(alpha, alpha_sens, beta_sens, alpha_spec, beta_spec))
}

get.oneparm.prob = function(x){
  p = logistic(x[1])[[1]]
  # Return the adjusted probability
  return(x[2]*p + (1-x[3])*(1-p))
}

# ----------------------------------------------------------------------------------
# Stan models

# Logit classifiation error model in Stan. Provides
# time series estimate.
logit.stan <- "
data {
  int<lower=0> N; // observations
  int<lower=0> K; // time periods - 1
  int<lower=0,upper=1> y[N]; // response vector
  matrix [N, K] X; // excludes first time period

  // prior means for b parameters -- 25-1 time periods
  vector[K] mu;

  // prior mean for a parameter
  real mu_a;

  // prior parameters for beta distribution 
  // (classification error)
  real alpha_sens; // sensitivity
  real beta_sens;
  real alpha_spec; // specificity
  real beta_spec;
}
parameters {
  real a; // coeff. for the first time of period
  vector[K] b; // coeff. for time periods - 1
  real<lower=0,upper=1> eta;   // sensitivity
  real<lower=0,upper=1> theta; // specificity
}

transformed parameters {
  vector[N] p;
  p = inv_logit(a + X * b);
}

model {
  // prior for intercept (mean D1)
  a ~ normal(mu_a, .25);

  // prior for magazine coeffs
  for(i in 1:K) {
    b[i] ~ normal(mu[i], .25);
  }

  // priors for classification error
  eta ~ beta(alpha_sens, beta_sens);
  theta ~ beta(alpha_spec, beta_spec);

  // likelihood
  y ~ bernoulli(p*eta + (1-theta)*(1-p));
}
"

# ----------------------------------------------------------------------------------
# Estimation functions

estimate.error <- function(vname, df, dums){
  # Hyperparameters for coefficients
  nhyper = get.normal.hyper(df[[vname]], df$time)
  alpha = nhyper$alpha[1]
  coeff = nhyper$coeff
  
  # Hyperparameters for eta and theta
  bhyper = get.beta.hyper(vname)
  alpha_sens = bhyper[[1]]$eta[1]
  beta_sens = bhyper[[1]]$eta[2]
  alpha_spec = bhyper[[1]]$theta[1]
  beta_spec = bhyper[[1]]$theta[2]
  
  # Prepare data
  data_list = list(N=nrow(df), 
                   K = ncol(dums), 
                   y=df[[vname]], 
                   X = dums, 
                   mu = coeff,
                   mu_a = alpha,
                   alpha_sens = alpha_sens,
                   beta_sens = beta_sens,
                   alpha_spec = alpha_spec,
                   beta_spec = beta_spec)
  
  # Fit model
  fit <- stan(model_code = logit.stan, data=data_list,
              iter=5000, chains=1, seed = 1234, 
              control= list(adapt_delta = 0.95))
  
  # Extract posterior
  post = as.data.frame(extract.samples(fit))
  cut = ncol(dums) + 1 + 2  # keep the necessary columns
  post = post[,1:cut]
  
  coeff_labels = names(post)[2:(length(names(post))-2)]
  ests = as.data.frame(init.prob(coeff_labels, post))
  names(ests) = c("low", "est", "up")
  ests$label = vname
  return(ests)
}

