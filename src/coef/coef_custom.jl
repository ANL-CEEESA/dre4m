# vim: tabstop=2 shiftwidth=2 expandtab colorcolumn=80
#############################################################################
#  Copyright 2022, David Thierry, and contributors
#  This Source Code Form is subject to the terms of the MIT
#  License.
#############################################################################

"""
    retrofit(baseKind::Int64, kind::Int64, time::Int64)
Returns the multiplier that modifies some of the coefficients of the base
technology. 
"""
function retroFit(baseKind, kind, time)::Tuple(Float64, Int64)
  multiplier = 1.
  baseFuel = baseKind
  if baseKind ∈ [0, 2] && kind == 0  #: carbon capture RF
    multiplier = carbCapOandMfact[baseKind]
  elseif baseKind ∈ [0, 2] && kind == 1  #: efficiencty RF
    multiplier = 1.  #: cost is the same
  elseif baseKind ∈ [1, 3, 4] && kind == 0 #: efficiency RF
    multiplier = 1.
  end
  if baseKind == 0
    if kind == 2  #: fuel-switch
      baseFuel = 2
    elseif kind == 3  #: fuel-switch
      baseFuel = 4
    end
  end
  return (mutiplier, baseFuel)
end
# thinking about this the retrofit could change a number of possible parameters
# from the model, say for example the capital, fixed, variable costs

# Operation and Maintenance (adjusted)
# (existing)
function wFixCost(mD::modData, baseKind::Int64, time::Int64) #: M$/GW
  #: Does not divide by the capacity factor
  #: We could change this with the age as well.
  cA = mD.ca
  iA = mD.ia
  discount = 1/((1.+iA.discountR)^time)
  return cA.fixC[baseKind+1, time+1]*discount
end
function wVarCost(mD::modData, baseKind::Int64, time::Int64) #: M$/GWh
  #: Based on generation.
  cA = mD.ca
  iA = mD.ia
  discount = 1/((1.+iA.discountR)^time)
  return cA.varC[baseKind+1, time+1]*discount
end

function xCapCost(mD::modData, baseKind::Int64, time::Int64) #: M$/GW
  #: Based on capacity.
  cA = mD.ca
  iA = mD.ia
  discount = 1/((1.+iA.discountR)^time)
  return cA.capC[baseKind+1, time+1]*discount
end

#: (retrofit)
#: Fixed cost
function zFixCost(mD::modData, rff::retrofForm, 
                  baseKind::Int64, kind::Int64, time::Int64) 
  #: M$/GW
  cA = mD.ca
  iA = mD.ia
  discount = 1/((1.+iA.discountR)^time)

  #: evaluate retrofit
  r = rff.rFix(baseKind, kind time)
  (multiplier, baseFuel) = (1., baseKind)
  if typeof(r) != nothing
    (multiplier, baseFuel) = r
  end
  #:

  fixCost = multiplier * cA.fixC[baseFuel+1, time+1]
  return fixCost*discount
end

#: (retrofit)
#: Variable cost
function zVarCost(mD::modData, rff::retrofForm,
                  baseKind::Int64, kind::Int64, time::Int64) 
  #: M$/GWh
  cA = mD.ca
  iA = mD.ia
  discount = 1/((1.+iA.discountR)^time)
  
  #: evaluate retrofit
  r = rff.rVar(baseKind, kind time)
  (multiplier, baseFuel) = (1., baseKind)
  if typeof(r) != nothing
    (multiplier, baseFuel) = r
  end
  #:

  varCost = multiplier * cA.varC[baseFuel+1, time+1]
  return varCost*discount
end

#: (retrofit)
# retrofit overnight capital cost (M$/GW)
function zCapCost(mD::modData, rff::retrofForm,
                  baseKind::Int64, kind::Int64, time::Int64) 
  #: M$/GW
  cA = mD.ca
  iA = mD.ia
  #discount = discount already comes from source
  
  #: evaluate retrofit
  r = rff.rCap(baseKind, kind time)
  (multiplier, baseFuel) = (1., baseKind)
  if typeof(r) != nothing
    (multiplier, baseFuel) = r
  end
  #:

  capCost = multiplier * xCapCost(mD, baseKind, time)

  return capCost
end

function retireCostW(mD::modData, kind::Int64, time::Int64, age::Int64) 
  #: M$/GW
  cA = mD.ca
  iA = mD.ia
  discount = 1/((1.+iA.discountR)^time)
  baseAge = time - age > 0 ? time - age: 0.
  #: Loan liability
  loanFrac = max(iA.loanP - age, 0)/iA.loanP
  loanLiability = loanFrac*cA.capC[kind+1, baseAge+1] * discount
  #: Decomission
  decom = cA.decomC[kind+1, age+1] * discount
  #:
  effSrvLf = max(iA.servLife[kind+1] - age, 0)
  return loanLiability + decom # lostRev*365*24
end

function saleLost(mD::modData, kind::Int64, time::Int64, age::Int64) 
  #: M$/GWh
  cA = mD.ca
  iA = mD.ia
  discount = 1/((1.+iA.discountR)^time)
  effSrvLf = max(iA.servLife[kind+1] - age, 0)
  #: we need the corresponding capacity factor afterwrds
  lostRev = effSrvLf*cA.elecSale[kind+1,time+1] * discount
  return lostRev*365*24
end


#: existing plant heat rate, (hr0) * (1+increase) ^ time
function heatRateW(mD::modData, kind::Int64, age::Int64, 
                    time::Int64, maxBase::Int64)
  tA = mD.ta
  iA = md.ia
  if age < time # this case does not exists
    return 0
  else
    baseAge = age - time
    baseAge = min(maxBase, baseAge)
    return tA.heatRw[kind+1, baseAge+1] * (1.+iA.heatIncR)^time
  end
end

#: (retrofit)
#: HeatRate
function heatRateZ(mD::modData, baseKind::Int64, kind::Int64, 
                   age::Int64, time::Int64, maxBase::Int64)
  tA = mD.ta
  iA = md.ia
  if age < time # this case does not exists
    return 0
  else
    #: evaluate retrofit
    r = rff.rHtr(baseKind, kind time)
    (multiplier, baseFuel) = (1., baseKind)
    if typeof(r) != nothing
      (multiplier, baseFuel) = r
    end
    #:
    #? fuelKind
    baseAge = age - time
    baseAge = min(maxBase, baseAge)
    heatrate = (tA.heatRw[baseFuel+1, baseAge+1]*(1.+iA.heatIncR)^time)
      return heatrate * multiplier
  end
end
##

function heatRateX(mD::modData, baseKind::Int64, kind::Int64, 
                   age::Int64, time::Int64)
  tA = mD.ta
  iA = md.ia
  if time < age
    return 0
  end
  baseTime = time - age # simple as.
  baseTime = max(baseTime - xDelay[baseKind], 0) 
  #but actually if it's less than 0 just take 0
  return tA.heatRx[baseKind+1, baseTime+1] * (1 + heatIncreaseRate) ^ time
end

#: (retrofit)
#: Carbon instance
function carbonIntW(mD::modDota, baseKind::Int64, kind::Int64=-1)
  tA = mD.ta
  iA = md.ia
  (multiplier, baseFuel) = (1., baseKind)
  #:
  return iA.carbInt[baseFuel+1] * multiplier
end

#: fuel costs only include those techs that are based in fuel burning
function fuelCostW(mD::modData, baseKind::Int64, 
                   time::Int64, kind::Int64=-1)
  tA = mD.ta
  cA = mD.ca
  iA = md.ia
  discount = 1/((1.+iA.discountR)^time)
  (multiplier, baseFuel) = (1., baseKind)
  return cA.fuelC[baseFuel+1, time+1]*discount 
end


#: (retrofit)
#: Carbon instance
function carbonIntZ(mD::modDota, rff::retrofForm, 
                    baseKind::Int64, kind::Int64=-1)
  tA = mD.ta
  iA = md.ia

  #: evaluate retrofit
  r = rff.rCof(baseKind, kind time)
  (multiplier, baseFuel) = (1., baseKind)
  if typeof(r) != nothing
    (multiplier, baseFuel) = r
  end
  #:
  return iA.carbInt[baseFuel+1] * multiplier
end

#: fuel costs only include those techs that are based in fuel burning
function fuelCostZ(mD::modData, rff::retrofForm,
                   baseKind::Int64, time::Int64, kind::Int64=-1)
  tA = mD.ta
  cA = mD.ca
  iA = md.ia
  discount = 1/((1.+iA.discountR)^time)

  #: evaluate retrofit
  r = rff.rCof(baseKind, kind time)
  (multiplier, baseFuel) = (1., baseKind)
  if typeof(r) != nothing
    (multiplier, baseFuel) = r
  end
  #:
  return cA.fuelC[baseFuel+1, time+1]*discount 
end

