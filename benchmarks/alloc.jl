# alloc.jl -- host allocation profile (wall time, GC time, allocated bytes) of a
# fixed solve, over REPS repetitions, seeded.
#
# This is one half of an A/B: run it on the code state you want to measure and
# tag it with LABEL (e.g. `before` / `after`). The manuscript's Figure 3 compares
# two isolated changes (the single-matrix branched-configuration set and the
# off-heap contraction temporaries) per device; reproducing that split needs the
# corresponding pre-change commit(s) of SpinGlassPEPS.jl -- see run_all.sh and the
# README. @timed measures the *host* Julia heap (GC time / bytes), which is what
# the allocation work targeted.
#
# ENV: SPINS=2048 SPARSITY=dense BOND=32 DEVICE=cpu|gpu REPS=Int SEED=Int
#      LABEL=str  OUT=path(append)  PKG=SpinGlassPEPS.jl checkout
using SpinGlassPEPS
using SpinGlassPEPS.SpinGlassEngine: no_merge
import CUDA
using Random, Printf

const SPINS    = parse(Int, get(ENV, "SPINS", "2048"))
const SPARSITY = get(ENV, "SPARSITY", "dense")
const BOND     = parse(Int, get(ENV, "BOND", "32"))
const DEVICE   = get(ENV, "DEVICE", "cpu")
const REPS     = parse(Int, get(ENV, "REPS", "3"))
const SEED     = parse(Int, get(ENV, "SEED", "1"))
const LABEL    = get(ENV, "LABEL", "after")
const OUT      = get(ENV, "OUT", "alloc_raw.csv")
const PKG      = get(ENV, "PKG", normpath(joinpath(@__DIR__, "..", "..", "SpinGlassPEPS.jl")))

const onGPU = DEVICE == "gpu"
onGPU && !CUDA.functional() && error("DEVICE=gpu but CUDA is not functional here")

const INSTS = Dict(
    128  => (joinpath(PKG, "test", "engine", "instances", "chimera_droplets", "128power", "001.txt"), (4, 4, 8)),
    2048 => (joinpath(PKG, "test", "engine", "instances", "chimera_droplets", "2048power", "001.txt"), (16, 16, 8)),
)
const inst, (m, n, t) = INSTS[SPINS]
const Sp = SPARSITY == "sparse" ? Sparse : Dense

const ph = potts_hamiltonian(ising_graph(inst); spectrum = full_spectrum,
    cluster_assignment_rule = super_square_lattice((m, n, t)))

function one_solve()
    net = PEPSNetwork{SquareSingleNode{GaugesEnergy},Sp,Float64}(m, n, ph, rotation(0))
    ctr = MpsContractor(Zipper, net,
        MpsParameters{Float64}(; bond_dim = BOND, var_tol = 1e-8, num_sweeps = 4, tol_SVD = 1e-16);
        onGPU = onGPU, beta = 3.0, graduate_truncation = true)
    onGPU && CUDA.synchronize()
    st = @timed res = low_energy_spectrum(ctr,
        SearchParameters(; max_states = 128, cutoff_prob = 0.0), no_merge; show_progress = false)
    onGPU && CUDA.synchronize()
    e = first(first(res).energies)
    clear_memoize_cache()
    (st.time, st.gctime, st.bytes, e)
end

one_solve()  # warm up JIT; not recorded

if !isfile(OUT)
    open(OUT, "w") do io
        println(io, "label,spins,sparsity,bond,device,rep,seed,wall_s,gc_s,alloc_bytes,energy")
    end
end
for rep in 1:REPS
    s = SEED + rep
    Random.seed!(s)
    onGPU && CUDA.seed!(s)
    (wall, gc, bytes, e) = one_solve()
    open(OUT, "a") do io
        @printf(io, "%s,%d,%s,%d,%s,%d,%d,%.6f,%.6f,%d,%.8f\n",
            LABEL, SPINS, SPARSITY, BOND, DEVICE, rep, s, wall, gc, bytes, e)
    end
    @printf("  [%s/%s] rep %d/%d  wall=%.2fs  gc=%.2fs  alloc=%.2f GiB  E=%.4f\n",
        LABEL, DEVICE, rep, REPS, wall, gc, bytes / 2^30, e)
    flush(stdout)
end
