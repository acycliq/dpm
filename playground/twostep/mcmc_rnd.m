% Run MCMC to generate samples from a probability density function. 

% Suppose we have data generated from a multimodal multivariate normal 
% distribution, mm_mvnpdf, then there are two possible problems to solve:
%
% 1.) Figuring out how to generate samples from such a distribution. 
%
% 2.) From observations infer the corresponding means.

clear all
clear
clf

addpath("likelihood")
addpath("pdf")
addpath("helpers")

load pattern100_sigma0_1.data dataset K

limit_min=0;
limit_max=12;

% Create structures in form {:,:,k}
% Assume that each cluster has the same number of data points
for i = 1:K
	data(:,:,i) = dataset(i).data;
	mu(:,:,i) = dataset(i).mu;
	sigma(:,:,i) = dataset(i).sigma;
end
		
weights = (1/K)(ones(1,K));

printf("Size of the dataset: %i\n", length(data));

use_resets = false;
use_structure = true;

perform_inference = false;

% scale standard deviation of the proposal distribution
stddev_scale_0 = 0.01;
random_scale_0 = 10;

big_jump_probability = 0.5;

if (use_structure) 

else
	% When not using structural input, adjust stddev_scale to "better" value
	stddev_scale_0 = stddev_scale_0 * 10;
end
stddev_scale = stddev_scale_0;

K
% With around T=10,000 we find maybe a third of the modes. With T=50,000 we find the majority.
T=50000;

prob_walk = zeros(T+1, 1);

state_init = zeros(1, 2);
state_dim = size(state_init);

if (perform_inference)
	% State exists out of K mean variables (each in 2D)
	state_walk = zeros(2,K,T+1);

	% Let's assume a window, 10x10 positive quadrant, and sample uniformly from it for the means
	window_min = 0;
	window_max = 10;
	prior.mu = unifrnd(window_min, window_max, 2, K);
	
	state_walk(:,:,1) = prior.mu;

	% we walk through a set of means
	% data comes from a mixture
	% suppose this mixture does have non-uniform weights or multiple mixture components are close to 
	% a data point, then we need to first segment our data into k clusters, and only then calculate the likelihood
	% for each set of data that belongs to a cluster

	%prob_walk(1) = mvnpdf_likelihood_multiple_mu(data, state_walk(:,:,1), control.sigma);
%	prob_walk(1) = mvnpdf_mixture_mu(data, state_walk(:,:,1), sigma);
	prob_walk(1) = sum(mm_mvnpdf(data, state_walk(:,:,1), sigma));
else
	% State exists out of single data points (2D)
	state_walk = zeros(1,2,T+1);

	% Just single random vector
	state_walk(:,:,1) = rand(1,2) * random_scale_0;

	prob_walk(1) = mm_mvnpdf(state_walk(:,:,1), mu, sigma);
	%prob_walk(1) = mvnpdf_likelihood(state_walk(:,:,1), mu(:,:,1), sigma(:,:,1));
end

%printf("The random walk starts at:")
%disp(state_walk(:,:,1))

Treset=T/10;
Tmodes=1000;

burnin=0.1;

% We should separate the procedure:

% 1) Get a set of a samples from different modes, the only two things that are important are:
%    a) Make sure that if the samples are generated by counting rejections, that the high count is not caused by just 
%       having nowhere to go rather than being at a highly probable location.
%    b) Make sure that samples are not generated by only one mode. Do not set the average step size of the random
%       walk too low, if that's how is searched for other modes.
%    In a 2D space it is nice to have two independent jump directions: a minimum of 3 modes, e.g. one that goes 
%    vertical and another that goes horizontal (or diagonal).  
%    It might very well be useful to reset often to get to different modes. The Markov property of an MCMC chain is
%    not really useful when searching for modes.
%
% 2) Extract the modes from the samples, by maximizing/counting, etc. 
%
% 3) Come up with a jump proposal distribution for the macro-steps. Consider e.g. also multiples of these steps or 
%    fractions.

if (use_structure)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Get samples from several, distinct modes
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	if (perform_inference)
		state_walk = mode_samples_rnd(Tmodes, @sum_function, @mm_mvnpdf, data, control.sigma);
	else
		state_walk = mode_samples_rnd(Tmodes, @mm_mvnpdf, mu, sigma);
	end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Use samples to get the modes
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	topff = modes_rnd(state_walk);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Use modes to get mode jumping proposal distribution
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	structure_proposal_pdf = mode_proposal_pdf(topff);

	% start at place with nonzero probability
	state_walk(:,:,1) = topff(1,:);
	prob_walk(1) = mm_mvnpdf(state_walk(:,:,1), mu, sigma);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% MCMC
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

printf("Start normal MCMC\n");

for t = 1:T

	if (mod(t, T/10) == 0) 
		printf("At t=%i (out of total T=%i)\n", t, T)
	end

	% resets 
	if (use_resets)
		if (mod(t, Treset) == 0) 
			state_walk(:,:,t) = rand(1,2) * random_scale_0;
			prob_walk(t) = mm_mvnpdf(state_walk(:,:,t), mu, sigma);
		end
	end

	if (use_structure)

		% we use ff and a standard random generator
		proposal_pdf = mvnrnd(state_init, eye(2)*stddev_scale);
		
		% big step only once every step
		if (rand > big_jump_probability)
			% we pick one randomly in structure_proposal_pdf
			pick_r = randi(length(structure_proposal_pdf));

			proposal_pdf = proposal_pdf + structure_proposal_pdf(pick_r,:); 
		end
	else
		% we can use a standard random generator
		proposal_pdf = mvnrnd([0 0], eye(2)*stddev_scale);
	end

	% propose step using proposal distribution
	state_walk(:,:,t+1) = state_walk(:,:,t) + proposal_pdf;

	% and we can have a "complicated" pdf we sample from
	prob_walk(t+1) = mm_mvnpdf(state_walk(:,:,t+1), mu, sigma);

	if (prob_walk(t) != 0)
		pfrac=prob_walk(t+1)/prob_walk(t);
		alpha=min(1, pfrac);
		u=unifrnd(0,1);
		if (alpha <= u) 
			% reject
			state_walk(:,:,t+1) = state_walk(:,:,t);
			prob_walk(t+1) = prob_walk(t);
		end
	end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Burnin and thin
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if (use_resets)
	% burn every first items after a Treset
	selectset = find(repmat([zeros(1,burnin*Treset) ones(1,(1-burnin)*Treset)],1,T/Treset));
else
	% burn first items overall
	selectset = find([zeros(1,burnin*T) ones(1,(1-burnin)*T)]);
end
xvalues=state_walk(:,:,selectset);

% downsample
downsample=4;
xvalues=xvalues(:,:,1:downsample:end);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Visualizations
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

figure(1)
subplot(1,3,1)
plot(xvalues(:,1,:),xvalues(:,2,:),'.');
limits=[limit_min limit_max limit_min limit_max];
axis(limits, "square", "manual");
title("Samples");

subplot(1,3,2)

resolution=201;
t = linspace(limit_min, limit_max, resolution);
[cx cy] = meshgrid(t, t);
xx = [cx(:) cy(:)];

y = mm_mvnpdf(xx, mu, sigma);
yy = reshape(y, [resolution resolution]);
contour(t,t,yy);

%plot3(cx(:),cy(:)',y);
%mesh(data(:,1),data(:,2));

axis(limits, "square", "manual");
title("Probability density function");

% how is data organized?

subplot(1,3,3)
plot(data(:,1,:), data(:,2,:), '.');
axis(limits, "square", "manual");
title("Input data");

hold off;


