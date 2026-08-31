# Solution spread, with the Z2 gauge handled correctly.
#
# These instances carry no local fields (verified: no nonzero self-couplings in any
# of the 100 files), so E(s) = E(-s) exactly and every state has a degenerate partner
# at Hamming distance N. The Fig. 3(c) metric scores that mirror as a second
# "diverse" solution for free.
#
# Fixing the gauge by pinning one spin is NOT a valid repair: a state that differs
# from the mirror AT the pinned spin is mapped to the wrong representative and lands
# ~N away instead of ~0. Use the quotient distance instead, which needs no gauge
# choice and is the honest metric on configurations-modulo-flip:
#
#     dq(a,b) = min(d(a,b), N - d(a,b))       in [0, N/2]
#
using SpinGlassPEPS, CUDA
using SpinGlassPEPS.SpinGlassEngine: no_merge
using Statistics: median
using Random

const AR = 0.01
const BASE_SEED = parse(Int64, get(ENV, "SEED", "1"))

# Keep this mapping identical to sweep50.jl. Reusing one stream per instance
# holds the randomized contraction sketch fixed across beta values.
instance_seed(instance) = BASE_SEED + Int64(instance)

dq(a, b, N) = (d = sum(a .!= b); min(d, N - d))

"Greedy count of mutually distant solutions under a threshold on the quotient."
function nvalleys(states, N, thresh)
    chosen = Int[]
    for i in eachindex(states)
        all(dq(states[i], states[j], N) > thresh for j in chosen) && push!(chosen, i)
    end
    length(chosen)
end

function main()
    dir = joinpath(pkgdir(SpinGlassPEPS), "benchmark", "instances", "square_50x50")
    m, n, t = 50, 50, 1; N = m * n * t
    betas = parse.(Float64, split(get(ENV, "BETAS", "2.0,4.0,6.0"), ","))
    out = open(get(ENV, "OUT", "div3.csv"), "w")
    println(out, "instance,beta,energy,n_within,n_distinct_E,div_raw,div_quotient,",
                 "dq50,dq90,dqmax,raw_dmax,time_s,seed")
    flush(out)
    for k = 1:parse(Int, get(ENV, "NINST", "10")), β in betas
        seed = instance_seed(k)
        ph = potts_hamiltonian(ising_graph(joinpath(dir, lpad(k,3,'0')*".txt"));
                 spectrum=full_spectrum, cluster_assignment_rule=super_square_lattice((m,n,t)))
        net = PEPSNetwork{SquareSingleNode{GaugesEnergy},Dense,Float64}(m, n, ph, rotation(0))
        ctr = MpsContractor(Zipper, net,
            MpsParameters{Float64}(; bond_dim=8, var_tol=1e-8, num_sweeps=4, tol_SVD=1e-16);
            onGPU=false, beta=β, graduate_truncation=true)
        Random.seed!(seed)
        tt = @elapsed sol, _ = low_energy_spectrum(ctr,
                SearchParameters(; max_states=1024, cutoff_prob=0.0), no_merge;
                show_progress=false)
        Eb = minimum(sol.energies)
        keep = [i for i in eachindex(sol.energies) if sol.energies[i] - Eb < AR * 2 * abs(Eb)]
        ss = [collect(sol.states[i]) for i in keep]
        ib = argmin(sol.energies[keep])

        # raw Fig. 3(c) metric, for comparison with the published definition
        raw = let chosen = Int[]
            for i in eachindex(ss)
                all(sum(ss[i] .!= ss[j]) > N ÷ 2 for j in chosen) && push!(chosen, i)
            end
            length(chosen)
        end
        # distances to the best state, on the quotient
        dd = sort([dq(ss[i], ss[ib], N) for i in eachindex(ss)])
        q(f) = dd[clamp(ceil(Int, f * length(dd)), 1, length(dd))]
        rawmax = maximum(sum(ss[i] .!= ss[ib]) for i in eachindex(ss))
        # a "distinct valley" needs to clear half the quotient diameter, N/4
        vq = nvalleys(ss, N, N ÷ 4)

        println(out, "$k,$β,$Eb,$(length(keep)),",
                "$(length(unique(round.(sol.energies[keep], digits=9)))),",
                "$raw,$vq,$(q(0.5)),$(q(0.9)),$(dd[end]),$rawmax,$tt,$seed")
        flush(out)
        @info "inst $k β=$β" Eb raw vq dq50=q(0.5) dq90=q(0.9) dqmax=dd[end]
    end
    close(out)
end
main()
