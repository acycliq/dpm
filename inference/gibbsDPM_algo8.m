% A Gibbs sampling algorithm that uses auxiliary variables
%
% -- Function: c_st = gibbsDPM_algo8(y, hyperG0, alpha, niter, doPlot)
%     Apply Gibbs sampling with m auxiliary variables.
%
%     The data is provided in y. In case of dependent plus independent
%     variables as in a regression problem, y contains both.
%
%     The hyperparameters are provided in hyperG0.
%
%     The Dirichlet Process Mixture parameter is given through alpha.
%
%     The number of iterations is defined in niter.
%
%     There are three plotting options through doPlot. If it is 0 nothing will
%     be plotted, if it is 1 every step will be plotted, if it is 2 the plot
%     will be updated every iteration for all data points at once.
%
function c_st = gibbsDPM_algo8(y, hyperG0, alpha, niter, doPlot)

    if doPlot
        figure('name','Gibbs sampling for DPM');
        colormap('default');
        cmap = colormap;
    end

    % Have n data items
    n = size(y,2);

    % Prepare cluster statistics to return
    c_st = zeros(n, niter/2);

    % Create 200 tables, with m customers each
    m = zeros(1,200);

    % Assign to each data item a table index
    c = zeros(n, 1);

    % Initialisation
    for k=1:n
        % Assign to each data item a table index uniformly up to 30
        c(k) = ceil(30*rand);
        % Add to the table counter
        m(c(k)) = m(c(k)) + 1;

        switch (hyperG0.prior)
        case { 'NIW', 'NIG' }
            if m(c(k))>1
                % If there are already customers assigned, update the sufficient
                % statistics with the new data item
                U_SS(c(k)) = update_SS(y, k, U_SS(c(k)));
            else
                % If this is the first customer, draw sufficient statistics from
                % the hyper prior.
                U_SS(c(k)) = update_SS(y, k, hyperG0);
            end
        case 'DPM_Seg'
             % Nothing to do..., there are no sufficient statistics
        otherwise
        end
    end

    printf("Number of customers at each table:\n");
    tables = find(m)
    customers = m(find(m))

    % Sample parameters for the tables (unique indices in customer allocation
    % array c)
    ind = unique(c);
    for j=1:length(ind)
        switch (hyperG0.prior)
        case { 'NIW', 'NIG', 'DPM_Seg', 'Schedule' }
            R = sample_pdf(hyperG0);
            U_R(ind(j)) = R;
        end
    end

    % N=20; test, generate assignments to 9 possible tables
    % c=floor(unifrnd(0,4,1,N))*2+3
    % y=(1:N)*10;
    % set m to number of customers at each table
    % [m,b]=hist(c,1:9)

    % Number of sampling steps is niter
    for i=2:niter
        % Update cluster assignments c
        for k=1:n
            % Remove data item k from the partition
            m(c(k)) = m(c(k)) - 1;

            % Assign new table index
            [c(k) update R] = sample_c(m, alpha, y(:,k), hyperG0, U_R);
            if (update)
              U_R(c(k)) = R;
            end

            % Add data item k to table indicated by index c
            m(c(k)) = m(c(k)) + 1;

            if doPlot==1
                some_plot(y, hyperG0, U_R, m, c, k, i, cmap)
            end
        end

        if doPlot==2
            some_plot(y, hyperG0, U_R, m, c, k, i, cmap)
        end
    
        printf("Number of customers at each table [step %i]:\n", i);
        tables = find(m)
        customers = m(find(m))

        printf("Likelihood\n");
        total_likelihood(m, y, hyperG0.prior, U_R, c);

        % This should be done differently, as e.g. in algo1 or algo2. However,
        % these can profit from conjugacy. Here we have to update without that.
        [dR] = update_c(m, alpha, y, hyperG0, U_R, c);
        U_R=dR;

        if i>niter/2
            c_st(:, i-niter/2) = c;
        end

        if doPlot==2
            some_plot(y, hyperG0, U_R, m, c, k, i, cmap)
        end

        print_clusters=true;
        if (print_clusters)
            fprintf('Iteration %d/%d\n', i, niter);
            fprintf('%d clusters\n\n', length(unique(c)));
        end
    end
end

% In this function we are not "allowed" to generate new clusters or delete one
% or more. We are change the parameters of the clusters that are identified
% using the data at hand. 
%
% Of course we shouldn't use maximum likelihood here (although we could try to
% fit the cluster parameters optimally to the data). No, we use another MCMC
% update here. We "blindly" propose new parameter values and check what the
% probability is that the observations are generated by this set of parameters.
%
% 1.) In the first implementation I used a random walk method (brownian) to 
% update the parameter values and subsequently allow for them with an alpha
% acceptance ratio as an MH step. This is what I'm using.
%
% 2.) I also experimented with multiple walkers in parallel (not tested).
%
% 3.) But probably what I should've done is just sampling from the prior.
% This is slower though. Dahl in "Sequentially-Allocated Merge-Split
% Sampler for Conjugate and Nonconjugate Dirichlet Process Mixture Models"
% (2005) goes for the random walk as well.
%
% We do not run this chain for many steps, just 100. At the end the
% parameters are updated in dR.
%
% Function: dR = update_c(m, alpha, z, hyperG0, U_R, c)
%
%  The cluster-size vector m, with cind = find(m) the non-empty clusters and 
%  U_R(cind) the cluster parameters to be updated. The data-cluster 
%  assignments c with find(c == cind(1)) the data item indices that belong to 
%  the first non-empty cluster. The vector z contains the actual data items.
% 
%  The parameter hyperG0 is used to (1) sample the cluster parameters, and 
%  (2) indicate which likelihood funtion should be used. TODO: rename it.
%
%  The parameter alpha is not used.
%
function [dR] = update_c(m, alpha, z, hyperG0, U_R, c)
    % set the default sampling method
    sampling_method='random_walk';

    % get indices of non-empty tables
    cind=find(m);
    % copy to result vector (will be overwritten in accept-reject step)
    dR = U_R;
    
    % Print current table indices
    cind
    
    % Print likelihood before we start updating
%    L = likelihoods(hyperG0.prior, repmat(z, 1, length(cind)), dR(cind) )

    print_struct_array_contents(true);
    dS = dR(cind);
    %disp_R = dR(cind);
    %rmfield(disp_R, 'a');
    %rmfield(disp_R, 'b');
    dT.mu = [dS.mu1; dS.mu2]';
    dT.kappa = [dS.kappa1; dS.kappa2]';
    dT.weights = [dS.weights0; dS.weights1; dS.weights2]';
    dT

    % Number of MH steps
    for tt=1:100
        % Iterate over all clusters
        %for j=1:length(cind)
        for i=1:length(cind)
            j = cind(i);
            % this shouldn't be the case
            switch(sampling_method)
            case 'random_walk'
                propR = brownian(dR(j), hyperG0.prior);
            case 'multiple_random_walks'
                % it's a nice idea to have multiple proposals, need to test it later
                mm=2;
                for l=2:mm
                    dR(l) = brownian(dR(1), hyperG0.prior);
                end
            case 'prior'
                propR = sample_pdf(hyperG0);
            end 
            % collect all data items that sit at the same table (cust is a vector)
            %cust=find(c == cind(j));
            cust=find(c == j);
            % likelihood that observations are generated by the proposal
            % (likelihood for one cluster, multiple observations)
            nprop_v = likelihoods(hyperG0.prior, z(:,cust), propR);
            nprop = prod(nprop_v);
            % likelihood that observations are generated by the existing pdf
            ncurr = prod(likelihoods(hyperG0.prior, z(:,cust), dR(j) ));
            if (ncurr)
                alpha2=nprop/ncurr;
                u=rand(1);
                % if nprop > ncurr, accept always. if not, accept by chance 
                % given by the ratio nprop/ncurr
                if (alpha2 > u)
                    dR(j)=propR;
                end
            else
                % ncurr==0 (starting from an unlucky area), accept every proposal
                dR(j)=propR;
            end
        end
    end
end

% In the end what is compared is a table with K customers with that of a table with N customers
% if N >> K, then the likelihood of that table is much smaller.
% This means that likelihood should not be properly scaled as a likelihood function: p(x|theta).
% If L(x|theta) = C * p(x|theta) the product L(x|theta)*L(x|theta) differs from 
% p(x|theta)*p(x|theta) with a factor C*C.

% Calculate likelihood that obervations are generated by this set of clusters
% by checking for each observation what the probability is that it has been 
% generated by this probability density (without consideration for prior)
%
% No, we want to know how likely the current set of observations is generated
% by one of the tables.
%
% No, given an assignment of observations to a table (multimodal thingy), we
% want to get the probability of that assignment. And we want this for each
% table. So, we can measure in "increasing fit" through higher and higher
% likelihoods per non-empty table. We can't just multiple or sum these, but
% a sum might be a good "approximation".
%
function total_likelihood(m, z, likelihood_type, U_R, c)
    % get non-empty tables
    cind=find(m);

    for i = 1:length(cind)
        j = cind(i);
        cust=find(c == j);

        % Calculate likelihood for every cluster (a cluster is multimodal pdf)
        L(i) = prod(likelihoods(likelihood_type, z(:,cust), U_R(j) ));
    end
    L
   
    [Lmax, Li ] = maximum(L, 2);

    for i = 1:length(Li)
        cluster=Li(i);
        likelihood = Lmax(i);

        % show a particularly good fitting table...
        tables = find(m);
        customers = m(find(m));
        j = cind(cluster);
        cust=find(c == j);

        table = j;
        observations_at_this_table = z(:,cust);
        parameters = U_R(j);
        likelihoods_at_this_table = likelihoods(likelihood_type, z(:,cust), U_R(j));
        
        disp(cluster);
        disp(likelihood);
        disp(table);
        disp(observations_at_this_table);
        disp(parameters);
        disp(likelihoods_at_this_table);
    end
end

% Use normal distribution as proposal distribution for all parameters.
% Note that this means that parameters might enter parts of the probability
% space that are actually not likely to be hit from the perspective of the
% prior. For example if the prior would only generate integers, a brownian
% motion would generate floats as well, which depending on the likelihood
% function might have zero probability of occurence.
function Rout = brownian(R, prior)
    scale = 0.1;
    switch(prior)
    case { 'NIW', 'NIG' }
        Rout.mu = R.mu + normrnd(0,1,size(R.mu));
        Rout.Sigma = R.Sigma + normrnd(0,1,size(R.Sigma));
    case 'DPM_Seg'
        Rout.mu = R.mu + normrnd(0,1,size(R.mu));
        Rout.Sigma = R.Sigma + normrnd(0,1,size(R.Sigma));
        Rout.a = R.a + normrnd(0,1,size(R.a));
        Rout.b = R.b + normrnd(0,1,size(R.b));
    case 'Schedule'
        Rout.a = R.a;
        Rout.b = R.b;
        Rout.mu1 = R.mu1 + scale * normrnd(0,1,size(R.mu1));
        Rout.mu2 = R.mu2 + scale * normrnd(0,1,size(R.mu2));
        % reflect kappa values, so they > 0
        Rout.kappa1 = abs(R.kappa1 + scale * normrnd(0,1,size(R.kappa1)));
        Rout.kappa2 = abs(R.kappa2 + scale * normrnd(0,1,size(R.kappa2)));
        Rout.weights0 = R.weights0;
        Rout.weights1 = R.weights1;
        Rout.weights2 = R.weights2;
    otherwise
    end
end

% Different from the conjugate case! In the conjugate case we could first
% establish the probability of sampling a new or existing cluster. Only after
% that we decided to sample from the new distribution.
% Now, in the nonconjugate case we have no closed-form description of the
% posterior probability, hence we actually have to sample from our prior.
% Then we treat the proposed cluster just as an existing one and calculate the
% likelihood in one sweep.
%
% Function: [K, update, R] = sample_c(m, alpha, z, hyperG0, U_R)
%
%  Given observation z, sample existing or new cluster.
%
function [K, update, R] = sample_c(m, alpha, z, hyperG0, U_R)

    % Neal's m, the number of auxiliary variables
    n_m=3;

    % Find first n_m empty tables
    emptyT = find(m==0, n_m);
    % This cluster does have not a number of customers, but alpha/m as weight
    m(emptyT) = alpha/n_m;
    % Get values from prior, to be used in likelihood calculation
    for i=1:length(emptyT)
        % Sample for this empty table
        switch(hyperG0.prior)
            case { 'NIW', 'NIG', 'DPM_Seg', 'Schedule' }
                R = sample_pdf(hyperG0);
                U_R(emptyT(i)) = R;
            otherwise
        end
    end

    % Indices of all clusters, both existing and proposed
    c = find(m~=0);

    Z = repmat(z, 1, length(c));

    % Calculate likelihood for every cluster
    L = likelihoods(hyperG0.prior, Z, U_R(c) );
    M = m(c);
    n = m(c).*L;
    % HELP
    % suddenly, we end up with sum(n) == 0
%    n
%    n = m(c).*likelihoods(hyperG0.prior, repmat(z, 1, length(c)), U_R(c) )';



    % Calculate b, as b=(N-1+alpha)/sum(n), of which the nominator (N-1+alpha)
    % gets cancelled out again, so we only require 1/const = 1/sum(n)
    const = sum(n);

    if (const == 0)
      % Sample random cluster
      ind = unidrnd(length(c));
      K = c(ind);
    else
      % Sample cluster in n according to their weight n(c)=m(c)*L(z,c)
      u=rand(1);
      ind = find(cumsum(n/const)>=u, 1 );
      K = c(ind);
    end

    % Set proposed tables to 0, except for table K
    setzero=setdiff(emptyT,K);
    m(setzero)=0;

    % The update flag is used to set U_mu/U_Sigma outside this function,
    % because octave/matlab doesn't support pass-by-reference
    update=true;
    if (length(setzero) == length(emptyT))
        update=false;
    end
end

% Plot mean values
function some_plot(z, hyperG0, U_R, m, c, k, i, cmap)
    switch (hyperG0.prior)
    case { 'NIG', 'DPM_Seg' }
        z=z(2:end,:);
    end
    ind=find(m);
    hold off;
    for j=1:length(ind)
        color=cmap(mod(5*ind(j),63)+1,:);
        mu = U_R(ind(j)).mu;

        switch (hyperG0.prior)
        case { 'DPM_Seg' }
            x_a(j) = U_R(ind(j)).a;
            x_b(j) = U_R(ind(j)).b;
        otherwise
            x_a(j)=-25;
            x_b(j)=+25;
        end
        y_a(j) = [1 x_a(j)]*mu;
        y_b(j) = [1 x_b(j)]*mu;
        plot([x_a(j) x_b(j)], [y_a(j) y_b(j)], '-', 'color', color, 'linewidth', 5);
        hold on
        switch (hyperG0.prior)
        case { 'DPM_Seg' }
            plot(x_a(j), y_a(j), '.', 'color',color, 'markersize', 30);
            plot(x_a(j), y_a(j), 'ok', 'linewidth', 2, 'markersize', 10);
            plot(x_b(j), y_b(j), '.', 'color',color, 'markersize', 30);
            plot(x_b(j), y_b(j), 'ok', 'linewidth', 2, 'markersize', 10);
        end
        plot(z(1,c==ind(j)),z(2,c==ind(j)),'.','color',color, 'markersize', 15);
        cust=find(c == ind(j));
        for f = 1:length(cust)
          plot([x_a(j) z(1,cust(f))],[y_a(j) z(2,cust(f))], '-', 'color', color);
          plot([x_b(j) z(1,cust(f))],[y_b(j) z(2,cust(f))], '-', 'color', color);
        end
    end
    plot(z(1,k),z(2,k),'or', 'linewidth', 3)
    title(['i=' num2str(i) ',  k=' num2str(k) ', Nb of clusters: ' num2str(length(ind))]);
    xlabel('X');
    ylabel('Y');
    %y_max=max([z(2,:),y_a,y_b, 25]);
    %y_min=min([z(2,:),y_a,y_b, -25]);
    %x_max=max([z(1,:),x_a,x_b, 25]);
    %x_min=min([z(1,:),x_a,x_b, -25]);
    y_max = 25;
    y_min = -25;
    x_max = 25;
    x_min = -25;
    xlim([x_min x_max]);
    ylim([y_min y_max]);

    pause(.01)
end
