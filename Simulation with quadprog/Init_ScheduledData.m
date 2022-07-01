clear;
close all;
set(0,'defaulttextInterpreter','latex');
addpath('..\Data trajectories') %<-- makes problems sometimes (try add path manually for mysterious errors)
%% Init script for Data-driven Predicitive Control of a 3-DoF Helicopter.
%  See documentation for physical and mathematical background.
%  
%  Attached files:   
%   - Data_driven_MPC_ScheduledData.slx         <-- Simulink-model
%   - hankel_c.m                                <-- used in Controller
%   - Travel_traj.mat                           <-- contains QP matrices
%   - Elevation_traj.mat                        <-- contains QP matrices
%   - Data-driven MPC of 3-DoF Helicopters.pdf  <-- Documentation
%
%  Remark: hankel_r.m didn't work for code generation in Simulink

%% Data Generation

% Measurement noise ~Unif
NOISE = 0;
noise_bound_data = 1*pi/180; % noise in data generation
noise_bound_cl   = 1*pi/180; % noise in closed loop measurements

tsim = 31;         % Data-generation time
dt = 0.1;          % Step size for discretized dynamics

%Disturbance for PE             
u_disturb = 0.2;
t_disturb = 0.4;

%% System Setup 

x0 = [0*pi/180; 0; -30*pi/180; 0; 0; 0;]; % Starting position

n  = 6;  % system dimension
nu = 6;  % estimated dimension
m  = 2;  % Input dimension
p  = 3;  % Output dimension

L_true = 50;     % Prediction Horizon (L_true*dt seconds)
L = L_true + nu; % for convenience
N = tsim/dt + 1;  % Data length (N*dt seconds)

%% Data-driven Predictive Control Setup

% Setpoints to be reached (tracking trajectory)
u_T = [1.1447/2;  1.1447/2];     % input corresponding to y_T = 0 (see DataGen.m)
% Angle setpoints:
y_T1 = [0*pi/180; 0*pi/180; 0];    % alpha_s, beta_s, gamma_s
y_T2 = [90*pi/180; 0*pi/180; 0];   % alpha_s, beta_s, gamma_s
y_T3 = [0*pi/180; 0*pi/180; 0];    % alpha_s, beta_s, gamma_s
y_T4 = [0*pi/180; -30*pi/180; 0];  % alpha_s, beta_s, gamma_s

% Set point transition times:
T_Track = 5;
T_Track2 = 20;
T_Track3 = 30;

% Not important for now
lambda_beta = 0;

%% Quadratic Program Setup
%
%                 min       f(z)
%                 s.t.  A_eq*z = b_eq
%                       A_ineq*z <= b_ineq
%                       lb <= z <= ub
%
%           z = [alpha; u; y; us; ys; sigma; beta]

%%%%%%%%%%%%%%%%%%%%%%%%%% Input constraints %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% See documentation for force restrictions
u_min  = [0; 0];
u_max  = [0.98; 0.98]; %[0.98;0.83]
y_min = [-inf; -33*pi/180; -90*pi/180]; 
y_max = [inf; 33*pi/180; 90*pi/180];
lb = [-inf*ones(N-L+1,1); repmat(u_min,L,1); repmat(y_min,L,1); u_min; y_min; -inf*ones(p*L,1); -inf];
ub = [inf*ones(N-L+1,1) ; repmat(u_max,L,1); repmat(y_max,L,1); u_max; y_max;  inf*ones(p*L,1);  inf];

load('Travel_traj') % <-- all matrices already stored in there
H_t    = H;
Sy_t   = S_y;
Adyn_t = A_dyn;

load('Elevation_traj') % <-- all matrices already stored in there
H_e    = H;
Sy_e   = S_y;
Adyn_e = A_dyn;

%%%%%%%%%%%%%%%%%%%%%%%% Equality constraints %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% A_eq * z = b_eq

% Dynamics:
% A_dyn gets updated in closed loop
b_dyn = zeros((m+p)*L,1);

% Initial conditions:
A_init = [zeros(nu*m,N-L+1) eye(nu*m) zeros(nu*m,m*(L-nu)+p*L+m+p+p*L+1);
          zeros(nu*p,N-L+1) zeros(nu*p,m*L) eye(nu*p) zeros(nu*p,p*(L-nu)+m+p+p*L+1)];
% b_init gets updated in closed loop
      
% Terminal equality constraint:
A_TEC = [zeros((nu+1)*m,N-L+1) zeros((nu+1)*m,m*(L-nu-1)) eye((nu+1)*m) zeros((nu+1)*m,p*L) -repmat(eye(m),nu+1,1) zeros(m*(nu+1),p+p*L+1);
         zeros((nu+1)*p,N-L+1) zeros((nu+1)*p,m*L) zeros((nu+1)*p,p*(L-nu-1)) eye((nu+1)*p) zeros((nu+1)*p,m) -repmat(eye(p),nu+1,1) zeros(p*(nu+1),p*L+1)];
b_TEC = zeros((m+p)*(nu+1),1);

% alpha sums to 1
A_alpha1 = [ones(1,N-L+1) zeros(1,(m+p)*L+m+p+p*L+1)];
b_alpha1 = 1;

%%%%%%%%%%%%%%%%%%%%%%% Inequality constraints %%%%%%%%%%%%%%%%%%%%%%%%%%%%
% no inequality constraints besides input bounds

%% Simulation

T_sim = 40; % Simulation time in seconds

simout = sim('Data_driven_MPC_ScheduledData.slx');

% Read out signals
t        = simout.tout;
u_cl     = simout.input.Data;
y_cl     = simout.output.Data;
y_s      = simout.setpoint.Data;
sigma    = simout.slack.Data;
y_T      = simout.trajectory.Data;
compTime = simout.compTime.Data;

% Tracking error
e_mat = (y_cl-y_T)'*(y_cl-y_T); % error matrix
e = dt/(T_sim+dt)*(e_mat(1,1)+3*e_mat(2,2)) * 180/pi% only take alpha and beta tracking error
e_ss = norm(y_T(t==20,1:2)-y_cl(t==20,1:2)) * 180/pi
cputime = mean(compTime)

% Convert to Degree
y_cl  = y_cl*180/pi;
y_s   = y_s*180/pi;
y_T   = y_T*180/pi;
sigma = sigma*180/pi;

%% Plots

% Control inputs:
figure(1)
subplot(2,1,1)
stairs(t,u_cl(:,1))
hold on
grid on
yline(u_T(1),'r')
legend('u_1','u_{1,s}')
%
subplot(2,1,2)
stairs(t,u_cl(:,2))
hold on
grid on
yline(u_T(2),'r')
legend('u_2','u_{2,s}')
%
sgtitle('Control Inputs')

% Plant outputs:
figure(2)
subplot(3,1,1)
hold all
plot(t,y_cl(:,1),'Linewidth',1.5);
plot(t,y_T(:,1),'Linewidth',1);
plot(t,y_s(:,1))
grid on
ylabel('$\alpha$')
legend('$\alpha$','$\alpha_{goal}$','$\alpha_s$','Interpreter','latex','Location','NorthEast')
%
subplot(3,1,2)
hold all
plot(t,y_cl(:,2),'Linewidth',1.5);
plot(t,y_T(:,2),'Linewidth',1);
plot(t,y_s(:,2))
grid on
ylabel('$\beta$')
legend('$\beta$','$\beta_{goal}$','$\beta_s$','Interpreter','latex','Location','NorthEast')
%
subplot(3,1,3)
plot(t,y_cl(:,3),'Linewidth',1.5);
hold on
grid on
legend('\gamma','Location','SouthEast')
ylabel('$\gamma$')
xlabel('time in s')
%
sgtitle('Plant Outputs')

% Real-time ability:
figure
stairs(t,compTime)
grid on
hold on
yline(dt)
ylabel('Computation time')
xlabel('Simulation time')
title('Real-time ability')

% % Slack variable sigma
% figure
% stairs(t,sigma)
% grid on
% title('Slack Variable $\sigma$')
% ylabel('$\sigma$')
% xlabel('time in s')

% Operational Coverage:
% figure
% hold all
% plot(y_cl(:,1),y_cl(:,2),'r-x')
% plot(y_T(:,1),y_T(:,2),'b')
% plot(yd(1,:),yd(2,:),'g-x')
% grid on
% title('Operational Coverage')
%legend('Position','Reference position','Collected data')




