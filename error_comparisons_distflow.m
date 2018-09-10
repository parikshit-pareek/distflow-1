clear variables
close all
%%
define_constants;
load('alpha_function');
nsamples = 5000;
mpopt  = mpoption('out.all',0, 'verbose', 0);
mpopt2 = mpopt;
mpopt2.pf.alg = 'ISUM';
mpopt2.pf.radial.max_it = 500;
%%
zvect = zeros(nsamples,3);
% err = struct('fz', zeros(nsamples,1),...
%       'lossy', struct('norm2', zvect, 'max', zvect, 'avg', zvect, 'std', zvect),...
%       'lossless', struct('norm2', zvect, 'max', zvect, 'avg', zvect, 'std', zvect));
fzvect     = zeros(nsamples,1);
norm2lossy = zvect; maxlossy = zvect; avglossy = zvect; stdlossy = zvect;
norm2lossless = zvect; maxlossless = zvect; avglossless = zvect; stdlossless = zvect;

status = false(nsamples,1);
%%
parforstatus(nsamples, 0.1, 1);
parpool(60);
parfor k = 1:nsample
    parforstatus(nsamples, 0.1)
    [n,e] = single_feeder_gen();
    fz    = length(n.id);
    %% matpower case
    mpc = matpower_fmt(n,e,60);
    mpc = parallel_branch_join(mpc);
    % remove charging shunts which are not modeled in distflow
    mpc.branch(:,BR_B) = 0; 

    % set transformer tap to 1 since these are also not modled in
    % distflow
    mpc.branch(1,TAP) = 1;
    % to avoid extremely large voltage drops due to the ill-setup
    % transformer, reduce its impedance artificailly.
    mpc.branch(1,[BR_R,BR_X]) = mpc.branch(1,[BR_R,BR_X])/4;
    
    % solve matpower case
    r = runpf(mpc, mpopt);
    if ~r.success
        r = runpf(mpc, mpopt2);
        if ~r.success
            fprintf('MATPOWER convergence failed: Feeder size %d, iter %d\n', fz, iter)
            continue
        end
    end
    v  = r.bus(:, VM);
    pf = r.branch(:, PF);
    qf = r.branch(:, QF);
    %% lossy distflow
    alpha = f(fz,beta);
    [vlossy, pflossy, qflossy] = distflow_lossy(r, alpha);
    
    %% lossless distflow
    [vlossless, pflossless, qflossless] = distflow_lossy(r, 0.5);
    
    %% errors 
    fzvect(k) = fz;
    
    tmp = struct();
    tmp.lossy.v = v - vlossy;
    tmp.lossy.p = (pf - pflossy)/r.baseMVA;
    tmp.lossy.q = (qf - qflossy)/r.baseMVA;
    tmp.lossless.v = v - vlossless;
    tmp.lossless.p = (pf - pflossless)/r.baseMVA;
    tmp.lossless.q = (qf - qflossless)/r.baseMVA;
    % 2 norm 
    norm2lossy(k,:)    = [norm(tmp.lossy.v,2), norm(tmp.lossy.p,2), norm(tmp.lossy.q,2)];
    norm2lossless(k,:) = [norm(tmp.lossless.v,2), norm(tmp.lossless.p,2), norm(tmp.lossless.q,2)];
    
    % max error
    maxlossy(k,:)      = [max(abs(tmp.lossy.v)), max(abs(tmp.lossy.p)), max(abs(tmp.lossy.q))];
    maxlossless(k,:)   = [max(abs(tmp.lossless.v)), max(abs(tmp.lossless.p)), max(abs(tmp.lossless.q))];
    
    % avg error
    avglossy(k,:)      = [mean(abs(tmp.lossy.v)), mean(abs(tmp.lossy.p)), mean(abs(tmp.lossy.q))];
    avglossless(k,:)   = [mean(abs(tmp.lossless.v)), mean(abs(tmp.lossless.p)), mean(abs(tmp.lossless.q))];
    
    % std error
    stdlossy(k,:)      = [std(abs(tmp.lossy.v)), std(abs(tmp.lossy.p)), std(abs(tmp.lossy.q))];
    stdlossless(k,:)   = [std(abs(tmp.lossless.v)), std(abs(tmp.lossless.p)), std(abs(tmp.lossless.q))];
end

%% place results in a structure
err = struct('fz', fzvect,...
      'lossy', struct('norm2', norm2lossy, 'max', maxlossy, 'avg', avglossy, 'std', stdlossy),...
      'lossless', struct('norm2', norm2lossless, 'max', maxlossless, 'avg', avglossless, 'std', stdlossless));
%% filter result and save
mask = err.fz ~= 0;
err.fz = err.fz(mask);
for field = {'norm2', 'max', 'avg', 'std'}
    err.lossy.(field) = err.lossy.(field)(mask);
    err.lossless.(field) = err.lossless.(field)(mask);
end

save('error_results.mat', 'err')