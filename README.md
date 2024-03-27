
# DRE<sup>4</sup>M
### Decarbonization Roadmapping and Energy, Environmental, Economic, and Equity Analysis Model



<p class="aligncenter"> <img src="./docs/docs/img/Dream_logo_ANL_colors.svg" width="40%" height="40%"
title="dre4am fr"> </p>

This is the implementation of the framework for the planning of the
technological makeup of the industrial sector.

Motivated by the efforts to achieve carbon neutrality, the model of this
framework modifies the portfolio of technologies over time for the sector of
interest such that,

<ol type="a"> <li>Net Present Value (NPV) is minimized</li> <li>Constraint on
Greenhouse Emissions (GHG), e.g. carbon dioxide, is satisfied</li> <li>Demand of
the underlying commodity is satisfied</li> </ol>

The current implementation reflects a case study for the electric power sector.

The for a given initial set of capacities of different vintages, the space of
decisions include,

- *Retirement* of the existing capacities.
- *Retrofitting* the existing capacities to alternative characteristics.
- *Creation* of new capacities from a technology portfolio.

All the associated quantities with the deployments, e.g. CO<sub>2</sub>, heat
requirement, etc.

## Documentation

[Documentation](https://dthierry.github.io/dre4m/).

## Source Code Organization

|  Directory | Description       |
|------------|-------------------|
| test/      | testing files     |
| instance/  | case studies      |
| data/      | instance data     |
| src/       | source code       |
| docs/      | documentation src |


## Contributors

- David Thierry, Argonne National Laboratory, *ESIA division*
- Sarang Supekar, Argonne National Laboratory, *ESIA division*

## License
 
DRE<sup>4</sup>M (`dre4m`) is licensed under the 3-Clause BDS licence.
Additionally, DRE<sup>4</sup>M (`dre4m`) utilizes several dependencies, which
have their own licences. Please refer to their respective repositories for more
information about the licenses. 

