import Clp
Clp.Clp_Version()
# attempt multi-retrofits
#using SCIP

using JuMP
import XLSX
import Dates

initialTime = Dates.now()  # to log the results, I guess
fname0 = Dates.format(initialTime, "eyymmdd-HHMMSS")
fname = fname0  # copy name
@info("Started\t$(initialTime)\n")
@info("Out files:\t$(fname)\n")
mkdir(fname)
fname = "./"*fname*"/"*fname

run(pipeline(`echo $(@__FILE__)`, stdout=fname*"_.out"))
run(pipeline(`cat $(@__FILE__)`, stdout=fname*"_.out", append=true))


# Set arbitrary (new) tech for subprocess i
kinds_x = [
           1, # 0
           1, # 1
           1, # 2
           1, # 3
           1, # 4
           1, # 5
           1, # 6
           1, # 7
           1, # 8
           1, # 9
           1, # 10
          ]

techToId = Dict()
techToId["PC"] = 0
techToId["NGCT"] = 1
techToId["NGCC"] = 2
techToId["P"] = 3
techToId["B"] = 4
techToId["N"] = 5
techToId["H"] = 6
techToId["W"] = 7
techToId["SPV"] = 8
techToId["STH"] = 9
techToId["G"] = 10

# 0 Pulverized Coal (PC)
# 1 Natural Gas (NGGT) a turbine or smth
# 2 Natural Gas (NGCC)
# 3 Petroleum (P)
# 4 Biomass (B)
# 5 Nuclear (N)
# 6 Hydroelectric (H)
# 7 On-shore wind (W)
# 8 Solar PV (SPV)
# 9 Solar Thermal (STH)
# 10 Geothermal (G)

kinds_z = [4, # 0
           1, # 1
           2, # 2
           1, # 3
           1, # 4
           0, # 5
           0, # 6
           0, # 7
           0, # 8
           0, # 9
           0, # 10
          ]
#: coal
#: kind 0 := carbon capture
#: kind 1 := efficiency
#: kind 2 := coal --> NG
#: kind 3 := coal --> Biom
#: ngcc
#: kind 0 := carbon capture
#: kind 1 := efficiency
#: all else efficiency


#
# Set cardinality
# Subprocess
I = 11

open(fname*"_kinds.txt", "w") do file
  write(file, "kinds_z\n")
  for i in 0:I-1
    write(file, "$(kinds_z[i+1])\n")
  end
  write(file, "kinds_x\n")
  for i in 0:I-1
    write(file, "$(kinds_x[i+1])\n")
  end
end


# Time horizon
T = 35 


# util_cfs = capacity_factors
discountRate = 0.07
tcrit = 60

# Normal heat increase with ageing?
heatIncreaseRate = 0.001

# Determine the age of plant
discard = Dict()
for i in 0:I-1
  discard[i] = serviceLife[i+1]
  #global k = 0
  #for j in dis_mat[i+1, :]
  #  if j > 0
  #    print("found at $(k)\n")
  #    discard[i] = k
  #    break
  #  end
  #  global k += 1
  #end
end

# Tech for subprocess i (retrofit)
Kz = Dict()
for i in 0:I-1
  Kz[i] = kinds_z[i + 1] # redundant?
end
# Tech for subprocess i (new)
Kx = Dict()
for i in 0:I-1
  Kx[i] = kinds_x[i + 1]
end
# Age of existing asset of age i \in I
N = Dict()
for i in 0:I-1
  N[i] = discard[i]
end

# Age of the new asset of subproc i and tech k
Nx = Dict()
for i in 0:I-1
  for k in 0:Kx[i]-1
    Nx[(i, k)] = discard[i] # assume the same, simple as
  end
end

# Consider disaggregated retrofit age
#
# Added longevity for subprocess i/tech k
Nz = Dict()
for i in 0:I-1
  for k in 0:Kz[i]-1
    Nz[i, k] = N[i] + floor(Int, discard[i] * 0.20) # assume 20%
  end
end


# factor for fixed o&m for carbon capture
carbCapOandMfact = Dict(
                    0 => 2.130108424, #pc
                    1 => 1.17001519, # igcc
                    2 => 2.069083447
                    )


# MUSD/GWh
# perhaps x and z do not have the same values as w



# factor for carbon capture retrofit
CarbCapFact = Dict(
                0 => 0.625693161, #pc
                1 => 0.499772727, # igcc
                2 => 1.047898338
                )


# MUSD/GWh
# how much does the retrofit cost?

# Model creation
m = Model(Clp.Optimizer)
#m = Model(SCIP.Optimizer)


# Variables
#
# existing asset (GWh)
@variable(m, w[t = 0:T, i = 0:I-1, j = 0:N[i]] >= 0)
# this goes to N just because we need to constrain z at N-1

# retired existing asset
@variable(m, uw[t = 0:T, i = 0:I-1, j = 1:N[i]-1] >= 0)
# we don't retire at year 0 or at the last year i.e \{0, N}

xDelay = Dict([i => 0 for i in 0:I-1])
xDelay[techToId["PC"]] = 5
xDelay[techToId["NGCT"]] = 4
xDelay[techToId["NGCC"]] = 4
xDelay[techToId["N"]] = 10
xDelay[techToId["H"]] = 10

maxDelay = maximum(values(xDelay))

# new asset
@variable(m, x[t = -maxDelay:T, i = 0:I-1, 
               k = 0:Kx[i]-1, j = 0:Nx[(i, k)]] >= 0)
#: made a ficticious point Nx so we can know how much is retired because it
#: becomes too old

# retired new asset
@variable(m, ux[t = 0:T, i = 0:I-1, 
                k = 0:Kx[i]-1, j = 1:Nx[(i, k)]-1] >= 0)
# can't retire at j = 0

# retrofitted asset
@variable(m, 
          z[t=0:T, i=0:I-1, k=0:Kz[i]-1, j=0:Nz[i, k]] >= 0)
#: no retrofits at age 0

#: the retrofit can't happen at the end of life of a plant, i.e., j goes from
#: 0 to N[i]-12
#: the retrofit can't happen at the beginning of life of a plant, i.e. j = 0
#: made a ficticious point Nxj so we can know how much is retired because it
#: becomes too old

@variable(m,
          zp[t = 0:T, i = 0:I-1, k = 0:Kz[i]-1, j = 1:N[i]-1] >= 0)
#: zp only goes as far as the base age N

# retired retrofit
@variable(m, 
          uz[t = 0:T, i = 0:I-1, k = 0:Kz[i]-1, j = 1:(Nz[i, k]-1)] >= 0)
# can't retire at the first year of retrofit, jk = 0
# can't retire at the last year of retrofit, i.e. jk = |Nxj| 
#: no retirements at the last age (n-1), therefore only goes to n-2

# Equations
# w0 balance0
@constraint(m, 
          wbal0[t = 0:T-1, i = 0:I-1],
          w[t+1, i, 1] == w[t, i, 0])
# can't retire stuff at the beginning, can't retrofit stuff as well
#
#
# w balance0
@constraint(m, 
          wbal[t = 0:T-1, i = 0:I-1, j = 2:N[i]],
          w[t+1, i, j] == w[t, i, j-1] 
          - uw[t, i, j-1] 
          - sum(zp[t, i, k, j-1] for k in 0:Kz[i]-1)
         )
# at j = 1 wbal0 applies instead
# we need j=N to constrain z at j = N-1, simple as

# z at age 1 balance

@constraint(m, 
            zbal0[t = 0:T-1, i = 0:I-1, k = 0:Kz[i]-1],
            z[t+1, i, k, 1] == z[t, i, k, 0]
           )

# if a plant is retrofitted, we allow one year of operation, 
# i.e. uz does not appear

# z balance
@constraint(m, 
            zbalBase[t = 0:T-1, i = 0:I-1, 
                     k=0:Kz[i]-1, j=2:N[i]],
            z[t+1, i, k, j] == 
            z[t, i, k, j-1] 
            - uz[t, i, k, j-1]
            + zp[t, i, k, j-1]
           )
#: Remaining, meaning that these are timeframes that exceed the
#: age of a normal plant, thus no zp exists. 
@constraint(m, 
            zbalRemainingE[t = 0:T-1, i = 0:I-1, 
                           k=0:Kz[i]-1, j=(N[i]+1):Nz[i, k]],
            z[t+1, i, k, j] == 
            z[t, i, k, j-1] 
            - uz[t, i, k, j-1]
           )



# x at age 0 balance
@constraint(m,
            xbal0[t = 0:T-1, i = 0:I-1, k = 0:Kx[i]-1],
            x[t+1, i, k, 1] == x[t-xDelay[i], i, k, 0]
                )
#: leading time goes here
#
for t in -maxDelay:-1
  for i in 0:I-1
    for k in 0:Kx[i]-1
      fix(x[t, i, k, 0], 0, force=true)
    end
  end
end
#=
for t in 0:T
  for i in 0:I-1
    for k in 0:Kz[i]-1
      fix(uz[t, i, k, N[i]-1], 0, force=true)
      fix(zp[t, i, k, N[i]-1], 0, force=true)
    end
  end
end
=#


# x balance
@constraint(m,
            xbal[t = 0:T-1, i = 0:I-1, k = 0:Kx[i]-1, 
                 j = 2:Nx[(i, k)]],
                 x[t+1, i, k, j] == x[t, i, k, j-1] - ux[t, i, k, j-1]
                )
# don't allow new assets to be retired at 0


# Initial age distribution
# Just assign it to the vector from excel
wij = cap_mat 

@constraint(m,
            initial_w_E[i = 0:I-1, j = 0:N[i]-1],
            w[0, i, j] == wij[i+1, j+1]
           )
@constraint(m,
            initial_w_N[t = 1:T, i = 0:I-1],
            w[0, i, N[i]] == 0
           )
# no initial plant at retirement age is allowed

# Zero out all the remaining new plants of old tech
@constraint(m,
            w_age0_E[t = 1:T, i = 0:I-1],
            w[t, i, 0] == 0
           )


@constraint(m,
            z_age0_E[t = 1:T, 
                     i = 0:I-1, 
                     k=0:Kz[i]-1],
            z[t, i, k, 0] == 0
           )


# Zero out all the initial condition of the retrofits 
@constraint(m,
            ic_zE[i=0:I-1, k=0:Kz[i]-1, 
                  j=0:Nz[i, k]-1],
            z[0, i, k, j] == 0
           )


# No retrofit at the end of life of the original plant
#@constraint(m,
#            z_end_E[t=1:T, i=0:I-1, k=0:Kz[i]-1, jk=0:Nxj[(i, k, N[i]-1)]-1],
#            z[t, i, k, N[i]-1, jk] == 0
#           )

# initial condition new plants of new tech
@constraint(m,
          initial_x[i=0:I-1, k=0:Kx[i]-1, j=0:Nx[(i, k)]-1],
          x[0, i, k, j] == 0
         )

# Effective capacity old
@variable(m, W[t=0:T-1, 
               i=0:I-1, 
               j=0:N[i]-1])
@constraint(m, W_E0[t=0:T-1, 
                    i=0:I-1],
            W[t, i, 0] == w[t, i, 0]
           )
#: they have to be split as there are no forced retirements at time = 0
@constraint(m, W_E[t=0:T-1, i=0:I-1, j=1:N[i]-1],
            W[t, i, j] == 
            w[t, i, j] 
            - uw[t, i, j] 
            - sum(zp[t, i, k, j] for k in 0:Kz[i]-1)
           )

# Effective capacity retrofit
@variable(m, 
          Z[t=0:T-1, i=0:I-1, k=0:Kz[i]-1, j=0:(Nz[i, k]-1)]
         )

@constraint(m, Z_E0[t=0:T-1, i=0:I-1, k=0:Kz[i]-1],
            Z[t, i, k,  0] == z[t, i, k, 0] 
           )


@constraint(m, Z_baseE[t=0:T-1, i=0:I-1, 
                       k=0:Kz[i]-1, j=1:N[i]-1],
            Z[t, i, k, j] == 
            z[t, i, k, j] - uz[t, i, k, j] 
            + zp[t, i, k, j]
           )

#: There are no retrofits of W after N, but we still have to track the 
#: assets
@constraint(m, Z_remainingE[t=0:T-1, i=0:I-1, 
                            k=0:Kz[i]-1, j=N[i]:(Nz[i, k]-1)],
            Z[t, i, k, j] == 
            z[t, i, k, j] - uz[t, i, k, j] 
           )

            #z[t+1, i, k, 1] == 0
# Effective capacity new
@variable(m,
          X[t=0:T-1, i=0:I-1, 
            k=0:Kx[i]-1, 
            j=0:Nx[i, k]-1] 
          )


@constraint(m, X_E0[t=0:T-1, i=0:I-1, k=0:Kx[i]-1],
            X[t, i, k, 0] == #effCapInd_x[i, k, 0] * 
            x[t-xDelay[i], i, k, 0]
           )
#: oi!, leading time needed here
#
@constraint(m, X_E[t=0:T-1, i=0:I-1, k=0:Kx[i]-1, j=1:Nx[i, k]-1],
            X[t, i, k, j] == #effCapInd_x[i, k, j] * 
            (x[t, i, k, j] - ux[t, i, k, j])
           )
#: these are the hard questions

#: hey let's just create effective generation variables instead
#: it seems that the capacity factors are the same regardless of 
#: us having retrofits, new capacity, etc.
yrHr = 24 * 365  # hours in a year

@variable(m, Wgen[t=0:T-1, i=0:I-1, j=0:N[i]-1])
@variable(m, Zgen[t=0:T-1, i=0:I-1, k=0:Kz[i]-1, j=0:(Nz[i, k]-1)])
@variable(m, Xgen[t=0:T-1, i=0:I-1, k=0:Kx[i]-1, j=0:(Nx[i, k]-1)])

@constraint(m, WgEq[t=0:T-1, i=0:I-1, j=0:N[i]-1], 
            Wgen[t, i, j] == YrHr * cFactW[t, i, j]  * W[t, i, j]
            )
@constraint(m, ZgEq[t=0:T-1, i=0:I-1, k=0:Kz[i]-1, j=0:Nz[i, k]-1],
            Zgen[t, i, k, j] == YrHr * cFactZ[t, i, k, j] * Z[t, i, k, j]
            )
@constraint(m, XgEq[t=0:T-1, i=0:I-1, k=0:Kx[i]-1, j=0:Nx[i, k]-1],
            Xgen[t, i, k, j] = YrHr * cFactX[t, i, k, j] * X[t, i, k, j]
            )

# Demand (GWh)
d = Dict()
for t in 0:T-1
  d[(t, 0)] = d_mat[t+1]
end


@variable(m, sGen[t = 1:T-1, i = 0:I-1]) #: supply generated
#: Generation (GWh)
@constraint(m, sGenEq[t = 1:T-1, i = 0:I-1],
          (
          sum(Wp[t, i, j] for j in 0:N[i]-1) + 
          sum(Zp[t, i, k, j] for j in 0:(Nz[i, k]-1) 
          for k in 0:Kz[i]-1) +
          sum(Xp[t, i, k, j] for j in 0:(Nx[i, k]-1) 
          for k in 0:Kx[i]-1)
          ) ==
          sGen[t, i]
          )

# Demand
@constraint(m,
            dcCon[t = 1:T-1],
            sum(sGen[t, i] for i in 0:I-1) >= d[(t, 0)]
           )
## We might not be able to satisfy demand at t=0

@variable(m, msSlack[t=1:T-1, i=0:3] >= 0)

# Market share
#@constraint(m, ms_con[t = 10:T-1, i=0:3],
#            # old
#            sum(W[t, i, j] for j in 1:N[i]-1)
#            # retrofit
#            + sum(sum(Z[t, i, k, j] 
#                      for j in 1:Nz[i, k]-1)
#                  for k in 0:Kz[i]-1) 
#            # new
#            + sum(sum(X[t, i, k, j] for j in 0:Nx[i, k]-1) 
#                  for k in 0:Kx[i]-1)
#            >= ms_mat[i+1, t+1] * d[(t, 0)] # - msSlack[t, i]
#           )
#

# Upper bound on some new techs
upperBoundDict = Dict(
                      "B" => 1000/1e3 * 0.59, 
                      "N" => 1000/1e3 * 0.898, 
                      "H" => 1000/1e3 * 0.42)
#: Just do it directly using bounds on the damn variables

for tech in keys(upperBoundDict)
  id = techToId[tech]
  for t in 1:T-1
    for k in 0:Kx[id]-1
      #for j in 0:Nx[id, k]
      set_upper_bound(x[t, id, k, 0], upperBoundDict[tech])
      #end
    end
  end
end

xDelay = Dict([i => 0 for i in 0:I-1])

# Fuel for a plant at a particular year/tech/age
fuelBased = Dict(
               0 => true, # pc
               1 => true, # gt
               2 => true, # cc
               3 => true, # p
               4 => true, # b
               5 => true, # n
               6 => false, # h
               7 => false, # w
               8 => false, # s
               9 => false, # st
               10 => false # g
              )

co2Based = Dict(i=>false for i in 0:I-1)
co2Based[techToId["PC"]] = true
co2Based[techToId["NGCT"]] = true
co2Based[techToId["NGCC"]] = true
co2Based[techToId["P"]] = true
co2Based[techToId["B"]] = true

@variable(m, heat_w[t = 0:T-1, i = 0:I-1, j = 0:N[i]-1; fuelBased[i]])

@variable(m, 
          heat_z[t = 0:T-1, i = 0:I-1, k = 0:Kz[i]-1, j = 0:Nz[i, k]-1, 
                 ; fuelBased[i]])

@variable(m, 
          heat_x[t=0:T-1, i=0:I-1, 
                 k=0:Kx[i]-1, 
                 j=0:Nx[i, k]-1; fuelBased[i]])

# Trade in the values for actual generation. 
@constraint(m,
            heat_w_E[t=0:T-1, i=0:I-1, 
                     j=0:N[i]-1; fuelBased[i]],
            heat_w[t, i, j] == 
            Wgen[t, i, j] * heatRateWf(i, j, t, N[i]-1)
           )


@constraint(m,
            heat_z_E[t = 0:T-1, i = 0:I-1, k = 0:Kz[i]-1, 
                     j = 0:Nz[i, k]-1; fuelBased[i]],
            heat_z[t, i, k, j] == 
            Zgen[t, i, k, j] * heatRateZf(i, k, j, t, N[i]-1)
           )

@constraint(m,
            heat_x_E[t=0:T-1, i=0:I-1, k=0:Kx[i]-1, 
                     j=0:Nx[i, k]-1; fuelBased[i]],
            heat_x[t, i, k, j] == 
            Xgen[t, i, k, j] * heatRateXf(i, k, j, t) 
           )

# Carbon emission (tCO2)
@variable(m, 
          wE[t = 0:T-1, i = 0:I-1, j = 0:N[i]-1; co2Based[i]])

@variable(m, 
          zE[t=0:T-1, i=0:I-1, k=0:Kz[i]-1, j=0:Nz[i, k]-1; co2Based[i]])

@variable(m, 
          xE[t=0:T-1, i=0:I-1, k=0:Kx[i]-1, j=0:Nx[i, k]-1; co2Based[i]])


@constraint(m,
            e_wCon[t=0:T-1, i=0:I-1, 
                   j=0:N[i]-1; co2Based[i]],
            wE[t, i, j] == heat_w[t, i, j] * carbonIntensity(i)
           )

@constraint(m,
            e_zCon[t = 0:T-1, i = 0:I-1, k =0:Kz[i]-1, 
                   j=0:Nz[i, k]-1; co2Based[i]],
            zE[t, i, k, j] == 
            heat_z[t, i, k, j] * carbonIntensity(i, k)
           )

@constraint(m,
            e_xCon[t=0:T-1, i=0:I-1, k=0:Kx[i]-1, 
                   j=0:Nx[i, k]-1; co2Based[i]],
            xE[t, i, k, j] == heat_x[t, i, k, j] * carbonIntensity(i)
)

# (overnight) Capital for new capacity
@variable(m, xOcap[t=0:T-1, i=0:I-1])
@constraint(m, xOcapE[t=0:T-1, i=0:I-1],
            xOcap[t, i] == sum(
                               xCapCostGw[t, i] * x[t, i, k, 0]
                               for k in 0:Kx[i]-1
                              )
           )
#: You'd need to add an additional index if you have an upgraded new capacity.

# (overnight) Capital for retrofits

@variable(m, zOcap[t=0:T-1, i=0:I-1, k=0:Kz[i]-1])
@constraint(m, zOcapE[t=0:T-1, i=0:I-1, k=0:Kz[i]-1],
            zOcap[t, i, k] == sum(
                               zCapCostGw(i, k, t) * zp[t, i, k, j]
                               for j in 1:N[i]-1 #: only related to the base age
                              )
           )


# Operation and Maintenance for existing 
#: Do we have to partition this term?
@variable(m, wFixOnM[t=0:T-1, i=0:I-1])
@variable(m, wVarOnM[t=0:T-1, i=0:I-1])
j
@constraint(m,
            wFixOnM_E[t=0:T-1, i=0:I-1],
            wFixOnM[t, i] == 
            wFixCost(i, t) * sum(W[t, i, j] for j in 0:N[i]-1)
           )

@constraint(m,
            wVarOnM_E[t=0:T-1, i=0:I-1],
            wVarOnM[t, i] == 
            wVarCost(i, t) * sum(Wgen[t, i, j] for j in 0:N[i]-1)
           )


# O and M for retrofit
@variable(m, zFixOnM[t=0:T-1, i=0:I-1])
@variable(m, zVarOnM[t=0:T-1, i=0:I-1])

@constraint(m,
            zFixOnM_E[t=0:T-1, i=0:I-1],
            zFixOnM[t, i] == 
            sum(zFixCost(i, k, t) * Z[t, i, k, j] 
                  for k in 0:Kz[i]-1 
                  for j in 0:N[i]-1 #: only related to the base age
                  ))

@constraint(m,
            zVarOnM_E[t=0:T-1, i=0:I-1],
            zVarOnM[t, i] == 
            sum(zVarCost(i, k, t) * Zgen[t, i, k, j] 
                  for k in 0:Kz[i]-1 
                  for j in 0:N[i]-1 #: only related to the base age
                  ))


# O and M for new
@variable(m, xFixOnM[t=0:T-1, i=0:I-1])
@variable(m, xVarOnM[t=0:T-1, i=0:I-1])

@constraint(m,
            xFixOnM_E[t=0:T-1, i=0:I-1],
            xFixOnM[t, i] == 
            sum(xFixCost(i, t) * X[t, i, k, j] 
                for k in 0:Kx[i]-1 
                for j in 0:Nx[i, k]-1)
           )

@constraint(m,
            xVarOndM_E[t=0:T-1, i=0:I-1],
            xVarOnM[t, i] == 
            sum(xVarCost(i, t) * Xgen[t, i, k, j] 
                for k in 0:Kx[i]-1 
                for j in 0:Nx[i, k]-1)
           )

# Fuel
@variable(m, wFuelC[t=0:T-1, i=0:I-1; fuelBased[i]])

@variable(m, zFuelC[t=0:T-1, i=0:I-1; fuelBased[i]])

@variable(m, xFuelC[t=0:T-1, i=0:I-1; fuelBased[i]])

@constraint(m, wFuelC_E[t=0:T-1, i=0:I-1; fuelBased[i]],
            wFuelC[t, i] == 
            fuelDiscounted(i, t) * sum(heat_w[t, i, j]
                              for j in 0:N[i]-1) 
           )

@constraint(m, zFuelC_E[t=0:T-1, i=0:I-1; fuelBased[i]],
            zFuelC[t, i] == 
            sum(fuelDiscounted(i, t, k) * heat_z[t, i, k, j]
            for k in 0:Kz[i]-1 for j in 0:Nz[i, k]-1)
           )

@constraint(m, xFuelC_E[t=0:T-1, i=0:I-1; fuelBased[i]],
            xFuelC[t, i] == 
            fuelDiscounted(i, t) * sum(heat_x[t, i, k, j] 
                                              for k in 0:Kx[i]-1
                                              for j in 0:Nx[i, k]-1
                                             )
           )

@variable(m, 
          co2OverallYr[t=0:T-1]
          #1.49E+11 * 0.7
         )
# <= 6.71E+10 * 0.7)
# <=6.71E+10 * 0.7)

@constraint(m, co2OverallYrE[t=0:T-1],
            co2OverallYr[t] == 
            sum(wE[t, i, j] for i in 0:I-1 
                for j in 0:N[i]-1 if co2Based[i])
           + sum(zE[t, i, k, j] 
               for i in 0:I-1 
               for k in 0:Kz[i]-1 
               for j in 0:Nz[i, k]-1 
               if co2Based[i])
           + sum(xE[t, i, k, j] 
                 for i in 0:I-1 
                 for k in 0:Kx[i]-1 
                 for j in 0:Nx[i, k]-1 if co2Based[i])
           )

co22010 = 2.2584E+09
co2_2010_2015 = 10515700000.0
co22015 = co22010 - co2_2010_2015
co22050 = co22010 * 0.29

@constraint(m, co2Budget,
            sum(co2OverallYr[t] for t in 0:T-1)  <= 
            (co22010 + co22050) * 0.5 * 41 - co2_2010_2015
           )

@info("The budget: $((co22010 + co22050) * 0.5 * 41 - co2_2010_2015)")
#: Last term is a trapezoid minus the 2010-2015 gap


# Natural "organic" retirement
@variable(m, wOldRet[t=1:T-1, i=0:I-1])
@variable(m, zOldRet[t=1:T-1, i=0:I-1, k=0:Kz[i]-1])
@variable(m, xOldRet[t=1:T-1, i=0:I-1, k=0:Kx[i]-1])

@constraint(m, wOldRetE[t=1:T-1, i=0:I-1],
            wOldRet[t, i] == 
            retCostW(t, i, N[i]-1) * w[t, i, N[i]]
           )

@constraint(m, zOldRetE[t=1:T-1, i=0:I-1, k=0:Kz[i]-1],
            zOldRet[t, i, k] == 
            retCostW(t, i, N[i]-1) * z[t, i, k, Nz[i, k]]
           )


@constraint(m, xOldRetE[t=1:T-1, i=0:I-1, k=0:Kx[i]-1],
            xOldRet[t, i, k] == 
            retCostW(t, i, Nx[i, k]-1) * x[t, i, k, Nx[i, k]]
           )

# "Forced" retirement
@variable(m, wRet[i=0:I-1, j=1:N[i]-1])
@variable(m, zRet[i=0:I-1, k=0:Kz[i]-1, j=1:Nz[(i, k)]-1])
@variable(m, xRet[i=0:I-1, k=0:Kx[i]-1, j=1:Nx[(i, k)]-1])

@constraint(m, wRet_E[i=0:I-1, j=1:N[i]-1],
            wRet[i, j] == sum(retCostW(i, t, j) * uw[t, i, j] for t in 0:T-1)
           )

@constraint(m, zRet_E[i=0:I-1, k=0:Kz[i]-1, j=1:Nz[(i,k)]-1],
            zRet[i, k, j] 
            == sum(retCostW(i, t, min(j, N[i]-1)) * uz[t, i, k, j] 
            for t in 0:T-1)
            )


@constraint(m, xRet_E[i=0:I-1, k=0:Kx[i]-1, j=1:Nx[(i, k)]-1],
            xRet[i, k, j] == sum(retCostW(i, t, j) * ux[t, i, k, j]
            for t in 0:T-1)
           )

# Net present value
@variable(m, npv) # ≥ 1000. * 2000.)
@constraint(m, npv_e, 
            npv == 
            # overnight
            sum(
              zOcap[t, i, k]
              for t in 0:T-1
              for i in 0:I-1
              for k in 0:Kz[i]-1
              )
              +
            sum(
                xOcap[t, i]
                for t in 0:T-1
                for i in 0:I-1
               )
            # op and maintenance (fixed + variable)
            #: existing
            + sum(
                wFixOnM[t, i] + wVarOnM[t, i]
                 for t in 0:T-1 
                 for i in 0:I-1)
                 +
            #: retrofit
            + sum(
                zFixOnM[t, i] + zVarOnM[t, i]
                for t in 0:T-1
                for i in 0:I-1
                )
            #: new
            + sum(
                xFixOnM[t, i] + xVarOnM[t, i]
                for t in 0:T-1
                for i in 0:I-1
            )
            # cost of fuel
            + sum(
                  wFuelC[t, i] 
                  + zFuelC[t, i] 
                  + xFuelC[t, i] 
                  for t in 0:T-1 
                  for i in 0:I-1 if fuelBased[i]
                 )
            + sum(
                  wOldRet[t, i]
                  for t in 1:T-1
                  for i in 0:I-1
                 )
            + sum(
                  zOldRet[t, i, k]
                  for t in 1:T-1
                  for i in 0:I-1
                  for k in 0:Kz[i]-1)
            + sum(
                  xOldRet[t, i, k]
                  for t in 1:T-1
                  for i in 0:I-1
                  for k in 0:Kx[i]-1
                 )
            + sum(wRet[i, j] 
                  for i in 0:I-1 
                  for j in 1:N[i]-1
            )
            + sum(zRet[i, k, j]
                  for i in 0:I-1
                  for k in 0:Kz[i]-1
                  for j in 1:Nz[(i, k)]-1
                  )
            + sum(xRet[i, k, j]
                  for i in 0:I-1
                  for k in 0:Kx[i]-1
                  for j in 1:Nx[(i, k)]-1
                  )
           )


# Terminal cost
@variable(m, termCw[i=0:I-1, j=0:N[i]-1])

@variable(m, termCx[i=0:I-1,
                    k=0:Kx[i],
                    j=0:N[i]-1])

@variable(m, termCz[i=0:I-1, k=0:Kz[i]-1, 
                    j=0:Nz[i, k]-1])

@constraint(m, termCwE[i=0:I-1, j=0:N[i]-1],
            termCw[i, j] == retireCost[T-1, i, j] * W[T-1, i, j] 
           )

@constraint(m, termCxE[i=0:I-1, k=0:Kx[i]-1, 
                       j=0:Nx[i,k]-1],
            termCx[i, k, j] == retireCost[T-1, i, j] * X[T-1, i, k, j]
           )

@constraint(m, termCzE[i=0:I-1, k=0:Kz[i]-1, 
                       j=0:Nz[i, k]-1],
            termCz[i, k, j] == 
            retireCost[T-1, i, min(j, N[i]-1)] * Z[T-1, i, k, j]
           )

@variable(m, termCost >= 0)
@constraint(m, termCost ==
            sum(termCw[i, j] 
                for i in 0:I-1 
                for j in 0:N[i]-1)
            + sum(termCx[i, k, j]
                  for i in 0:I-1
                  for k in 0:Kx[i]-1
                  for j in 0:Nx[i, k]-1)
            + sum(termCz[i, k, j]
                  for i in 0:I-1
                  for k in 0:Kz[i]-1
                  for j in 1:Nz[i, k]-1)
           )

windIdx = 7

@constraint(m, windRatioI[t=1:T-1, i = 8:10],
            sum(X[t, i, k, 0] 
               for k in 0:Kx[i]-1
              )
            == 
            sum(X[t, windIdx, k, 0] * windRatio[i + 1]
                for k in 0:Kx[windIdx]-1
                ))
#: only applied on new allocations


@objective(m, Min, (npv
                   #+ 50/1e6 * co2Overall
                   #sum(co2OverallYr[t] for t in 0:T-1) #+
                   #1e-06 * sum(
                   #     xOcap[t, i]
                   #     for t in 0:T-1
                   #     for i in 0:I-1
                   #)
                   + (1e-6)* termCost
                   #+ 1e-3 * sum(msSlack)
                   )/1e3
          )


optimize!(m)

@info("objective\t$(objective_value(m))\n")

finalTime = Dates.now()  # to log the results, I guess
@info("End optimization\t$(finalTime)\n")

printstyled(solution_summary(m), color=:magenta)


@info("Done for good.\n")
@info("Out files:\t$(fname0)\n")

