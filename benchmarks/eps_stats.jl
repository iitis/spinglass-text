# eps_stats.jl -- contraction-error diagnostics ("Contraction error control" in
# the manuscript), seeded, one row per bond dimension.
#
# Protocol: 128power chimera instance (4x4x8), cluster spectra truncated to
# num_states_cl = 2^6 (brute_force), SquareSingleNode{GaugesEnergy}, Dense,
# SVDTruncate, beta = 1, num_sweeps = 1, graduate_truncation, ONE lattice
# transformation (rotation(0)), search with max_states = 2^4, cutoff_prob = 1e-4.
# This is the package's own "sweep reports contraction error" fixture
# (test/engine/sweep.jl); truncation statistics are read through the scoped
# TRUNCATION_LOG exactly as a user would (see examples/square_50x50.jl).
#
# Target: D=4  sum 3.15e-4, max 2.43e-4, bond-limited 18/18, kept/offered
# 108/307; D=32 sum 5.56e-14, max 5.51e-14, bond-limited 0/4, kept/offered
# 192/592; both E = -210.933334. All values reproduce bit-for-bit. The
# bond-limited flag counts only bond-capped truncations that discard more than
# numerically negligible weight (NEGLIGIBLE_DISCARD in SpinGlassTensors). Thus
# "0 bond-limited" means no change from raising D is expected at the reported
# precision: at D=32 the four bond-capped cuts drop eps_i <= 5.5e-14 and do not count.
# The stats are device-independent (CPU == GPU here).
#
# ENV: BONDS=csv of Ints (default "4,32")  SEED=Int  DEVICE=cpu|gpu
#      OUT=path  PKG=SpinGlassPEPS.jl checkout
# Usage: julia --project=$PKG eps_stats.jl
using SpinGlassPEPS
using SpinGlassPEPS.SpinGlassEngine: no_merge
using Base.ScopedValues: with
import CUDA
using Random, Printf

const BONDS  = parse.(Int, split(get(ENV, "BONDS", "4,32"), ","))
const SEED   = parse(Int, get(ENV, "SEED", "1"))
const DEVICE = get(ENV, "DEVICE", "cpu")
const OUT    = get(ENV, "OUT", "eps_stats.csv")
const PKG    = get(ENV, "PKG", normpath(joinpath(@__DIR__, "..", "..", "SpinGlassPEPS.jl")))

const onGPU = DEVICE == "gpu"
onGPU && !CUDA.functional() && error("DEVICE=gpu but CUDA is not functional here")

const inst = joinpath(PKG, "test", "engine", "instances", "chimera_droplets", "128power", "001.txt")
const m, n, t = 4, 4, 8

const ph = potts_hamiltonian(
    ising_graph(inst),
    2^6;                       # num_states_cl: truncated cluster spectra
    spectrum = brute_force,
    cluster_assignment_rule = super_square_lattice((m, n, t)),
)

function one_solve(bond)
    net = PEPSNetwork{SquareSingleNode{GaugesEnergy},Dense,Float64}(m, n, ph, rotation(0))
    ctr = MpsContractor(SVDTruncate, net,
        MpsParameters{Float64}(; bond_dim = bond, num_sweeps = 1);
        onGPU = onGPU, beta = 1.0, graduate_truncation = true)
    log = TruncationLog()
    sol = with(TRUNCATION_LOG => log) do
        first(low_energy_spectrum(ctr,
            SearchParameters(; max_states = 2^4, cutoff_prob = 1e-4),
            no_merge; show_progress = false))
    end
    s = truncation_stats(log)
    clear_memoize_cache()
    s, first(sol.energies)
end

open(OUT, "w") do io
    println(io, "bond,sum_eps,max_eps,bond_limited,truncations,kept,offered,energy")
end
for bond in BONDS
    Random.seed!(SEED)
    onGPU && CUDA.seed!(SEED)
    s, e = one_solve(bond)
    open(OUT, "a") do io
        @printf(io, "%d,%.6e,%.6e,%d,%d,%d,%d,%.6f\n",
            bond, s.discarded_sum, s.discarded_max, s.saturated, s.count,
            s.dims_kept, s.dims_offered, e)
    end
    @printf("  [%s] D=%-3d  sum_eps=%.3e  max_eps=%.3e  bond-limited=%d/%d  kept=%d/%d  E=%.6f\n",
        DEVICE, bond, s.discarded_sum, s.discarded_max, s.saturated, s.count,
        s.dims_kept, s.dims_offered, e)
    flush(stdout)
end
