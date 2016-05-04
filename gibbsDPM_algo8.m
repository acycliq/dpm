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
        colormap('default')
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
                U_SS(c(k)) = update_SS(y(:,k), U_SS(c(k)));
            else
                % If this is the first customer, draw sufficient statistics from
                % the hyper prior.
                U_SS(c(k)) = update_SS(y(:,k), hyperG0);
            end
        case 'DPM_Seg'
             % Nothing to do..., there are no sufficient statistics
        otherwise
        end
    end

    % Sample parameters for the tables (unique indices in customer allocation
    % array c)
    ind = unique(c);
    for j=1:length(ind)
        switch (hyperG0.prior)
        case 'NIW'
            R = sample_pdf(hyperG0);
            U_R(ind(j)) = R;
        case 'NIG'
            R = sample_pdf(hyperG0);
            U_R(ind(j)) = R;
        case 'DPM_Seg'
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

% This is another MCMC update.
% 1.) In the first implementation I used a random walk method (brownian) to 
% update the parameter values and subsequently allow for them with an alpha
% acceptance ratio as an MH step. 
% 2.) I also experimented with multiple walkers in parallel (not tested).
% 3.) But probably what I should've done is just sampling from the prior.
% This is slower though. Dahl in "Sequentially-Allocated Merge-Split
% Sampler for Conjugate and Nonconjugate Dirichlet Process Mixture Models"
% (2005) goes for the random walk.
function [dR] = update_c(m, alpha, z, hyperG0, U_R, c)
    % set the default sampling method
    sampling_method='random_walk';
    cind=find(m);
    % copy to result vector (will be overwritten in accept-reject step)
    dR = U_R;
    % Number of MH steps
    for tt=1:100
        % Iterate over all clusters
        for j=1:length(cind)
            % this shouldn't be the case
            switch(sampling_method)
            case 'random_walk'
                propR = brownian(dR(j), hyperG0);
            case 'multiple_random_walks'
                % it's a nice idea to have multiple proposals, need to test it later
                mm=2;
                for l=2:mm
                    dR(l) = brownian(dR(1), hyperG0);
                end
            case 'prior'
                propR = sample_pdf(hyperG0);
            end 
            % collect all data items that sit at the same table (cust is a vector)
            cust=find(c == cind(j));
            % likelihood that observations are generated by the proposal
            nprop = prod(likelihoods(hyperG0.prior, z(:,cust), propR ));
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

% Use normal distribution as proposal distribution for all parameters.
% Note that this means that parameters might enter parts of the probability
% space that are actually not likely to be hit from the perspective of the
% prior. For example if the prior would only generate integers, a brownian
% motion would generate floats as well, which depending on the likelihood
% function might have zero probability of occurence.
function Rout = brownian(R, hyperG0)
  switch(hyperG0.prior)
    case { 'NIW', 'NIG' }
      Rout.mu = R.mu + normrnd(0,1,size(R.mu));
      Rout.Sigma = R.Sigma + normrnd(0,1,size(R.Sigma));
    case 'DPM_Seg'
      Rout.mu = R.mu + normrnd(0,1,size(R.mu));
      Rout.Sigma = R.Sigma + normrnd(0,1,size(R.Sigma));
      Rout.a = R.a + normrnd(0,1,size(R.a));
      Rout.b = R.b + normrnd(0,1,size(R.b));
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
            case 'NIW'
                % Sample from the prior, not taken into account data items
                R = sample_pdf(hyperG0);
                U_R(emptyT(i)) = R;
            case 'NIG'
                R = sample_pdf(hyperG0);
                U_R(emptyT(i)) = R;
            case 'DPM_Seg' % Dirichlet Process Mixture of Segments
                R = sample_pdf(hyperG0);
                U_R(emptyT(i)) = R;
            otherwise
        end
    end

    % Indices of all clusters, both existing and proposed
    c = find(m~=0);

    % Calculate likelihood for every cluster
    n = m(c).*likelihoods(hyperG0.prior, repmat(z, 1, length(c)), U_R(c) )';

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
