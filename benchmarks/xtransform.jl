# Do different lattice transformations land in the same valley?
#
# Panel (d) shows that within one contraction order the returned states form a
# tight cluster. This asks the complementary question across contraction orders:
# decode each transformation's best state to Ising spins (verified consistent
# across transformations), quotient the Z2 gauge, and measure pairwise Hamming
# distance. Large distances mean the sweep samples genuinely distinct valleys
# rather than re-finding one.
using SpinGlassPEPS
using SpinGlassPEPS.SpinGlassNetworks: energy
using Printf
using Statistics: median

const M, N, T = 50, 50, 1
const NSPIN = M * N * T

"Decoded spins in ascending Ising-vertex order, plus the raw dict for auditing."
function decoded(ph, sol, i)
    d = decode_potts_hamiltonian_state(ph, collect(sol.states[i]))
    ks = sort(collect(keys(d)))
    [d[k] for k in ks], d
end

# These instances have no local fields, so E(s) = E(-s) and configurations are only
# defined up to a global flip. Pinning a spin to fix the gauge is fragile -- a state
# differing from the mirror AT the pinned spin is sent to the wrong representative,
# ~N away instead of ~0. The quotient distance needs no gauge choice.
dq(a, b, n) = (d = sum(a .!= b); min(d, n - d))

function main()
    dir = joinpath(pkgdir(SpinGlassPEPS), "benchmark", "instances", "square_50x50")
    out = open(get(ENV, "OUT", "xtransform.csv"), "w")
    println(out, "instance,n_ok,consensus,energy_spread,best_energy,d_min,d_med,d_max,n_valleys")
    flush(out)
    for k = 1:parse(Int, get(ENV, "NINST", "5"))
        ig = ising_graph(joinpath(dir, lpad(k, 3, '0') * ".txt"))
        ph = potts_hamiltonian(ig; spectrum = full_spectrum,
                cluster_assignment_rule = super_square_lattice((M, N, T)))
        sw = sweep_transformations(
            t -> MpsContractor(Zipper,
                    PEPSNetwork{SquareSingleNode{GaugesEnergy},Dense,Float64}(M, N, ph, t),
                    MpsParameters{Float64}(; bond_dim = 8, var_tol = 1e-8, num_sweeps = 4);
                    onGPU = false, beta = 4.0, graduate_truncation = true),
            SearchParameters(; max_states = 256, cutoff_prob = 0.0))

        ok = [i for i in eachindex(sw.solutions) if sw.solutions[i] !== nothing]
        vs = Vector{Vector{Int}}()
        for i in ok
            v, d = decoded(ph, sw.solutions[i], 1)
            Ed, Er = energy(ig, d), sw.solutions[i].energies[1]
            isapprox(Ed, Er; atol = 1e-6) ||
                @warn "decoded energy mismatch" instance = k transform = i Ed Er
            push!(vs, v)
        end

        ds = [dq(vs[a], vs[b], NSPIN) for a in eachindex(vs) for b in eachindex(vs) if a < b]
        valleys = Int[]     # distinct valleys: clear half the quotient diameter, N/4
        for a in eachindex(vs)
            all(dq(vs[a], vs[b], NSPIN) > NSPIN ÷ 4 for b in valleys) && push!(valleys, a)
        end
        r = sw.report
        Eb = minimum(s.energies[1] for s in sw.solutions if s !== nothing)
        dmin, dmed, dmax = isempty(ds) ? (0, 0, 0) :
                           (minimum(ds), round(Int, median(ds)), maximum(ds))
        @printf("inst %2d: ok=%d consensus=%d/%d spread=%.3e  d=[%d,%d,%d]/%d  valleys=%d\n",
                k, length(ok), r.consensus, length(sw.transformations), r.energy_spread,
                dmin, dmed, dmax, NSPIN, length(valleys))
        println(out, "$k,$(length(ok)),$(r.consensus),$(r.energy_spread),$Eb,",
                "$dmin,$dmed,$dmax,$(length(valleys))")
        flush(out)
    end
    close(out)
end
main()
