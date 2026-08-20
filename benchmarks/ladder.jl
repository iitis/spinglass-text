# ladder.jl -- beta-ladder warm-start benchmark (manuscript section "β ladder
# with warm-started boundary MPS").
#
# Protocol (the manuscript's Xeon reference run): 2048power instance (16x16x8,
# num_states_cl = 2^8), Zipper/Sparse, bond 16, beta schedule 1.5, 2.25, 3.0.
# Two arms walk the same schedule on fresh contractors:
#   cold  -- warm_start = false, max_discarded enabled, so every rung is an
#            independent solve whose contraction Σε is recorded and guarded;
#   warm  -- warm_start = true (and NO max_discarded: the guard cannot see a
#            warmed rung's error -- it reports ~zero discarded weight whatever
#            its accuracy -- and the package warns if the two are combined).
#            Warmed-rung Σε still comes from the truncation log and is ~0.
# Arms are interleaved within a round and their order alternates across rounds;
# a full GC.gc(true) (+ CUDA.reclaim() on device) runs before every arm -- see
# README.md, "Protocol notes".
#
# One raw row per (round, arm, rung) is appended to OUT, so a run can be resumed
# or inspected mid-flight. The first line of a fresh OUT is a '#' comment
# recording the CPU model and Julia version the file was created under.
#
# Smoke test (seconds):   SPINS=128 julia --project=$PKG ladder.jl
# Manuscript run (CPU):   CUDA_VISIBLE_DEVICES="" julia --project=$PKG ladder.jl
#
# ENV: SPINS=128|2048  BOND=Int  BETAS=comma list  ROUNDS=Int  SEED=Int
#      DEVICE=cpu|gpu  OUT=path(append)  PKG=SpinGlassPEPS.jl checkout
using SpinGlassPEPS
import CUDA
using Random, Printf, Statistics

const SPINS  = parse(Int, get(ENV, "SPINS", "2048"))
const BOND   = parse(Int, get(ENV, "BOND", "16"))
const BETAS  = parse.(Float64, split(get(ENV, "BETAS", "1.5,2.25,3.0"), ","))
const ROUNDS = parse(Int, get(ENV, "ROUNDS", "1"))
const SEED   = parse(Int, get(ENV, "SEED", "1"))
const DEVICE = get(ENV, "DEVICE", "cpu")
const OUT    = get(ENV, "OUT", "ladder_raw.csv")
const PKG    = get(ENV, "PKG", normpath(joinpath(@__DIR__, "..", "..", "SpinGlassPEPS.jl")))

const onGPU = DEVICE == "gpu"
onGPU && !CUDA.functional() && error("DEVICE=gpu but CUDA is not functional here")

const INSTS = Dict(
    128  => (joinpath(PKG, "test", "engine", "instances", "chimera_droplets", "128power", "001.txt"), (4, 4, 8)),
    2048 => (joinpath(PKG, "test", "engine", "instances", "chimera_droplets", "2048power", "001.txt"), (16, 16, 8)),
)

# num_states_cl = 2^8: both instance families have 8-spin clusters, so this is
# the full cluster spectrum, stated explicitly as in the manuscript.
const NUM_STATES_CL = 2^8
const SPARAMS = SearchParameters(; max_states = 2^8, cutoff_prob = 1e-4)

hamiltonian(inst, m, n, t) = potts_hamiltonian(
    ising_graph(inst), NUM_STATES_CL;
    spectrum = full_spectrum,
    cluster_assignment_rule = super_square_lattice((m, n, t)))

function contractor(ph, m, n)
    net = PEPSNetwork{SquareSingleNode{GaugesEnergy},Sparse,Float64}(m, n, ph, rotation(0))
    MpsContractor(Zipper, net,
        MpsParameters{Float64}(; bond_dim = BOND, var_tol = 1e-8, num_sweeps = 4, tol_SVD = 1e-16);
        onGPU = onGPU, beta = first(BETAS), graduate_truncation = true)
end

reclaim!() = (GC.gc(true); onGPU && CUDA.reclaim(); nothing)

# One arm = one ladder on a fresh contractor (beta_ladder mutates it). The cold
# arm carries the discarded-weight guard so Σε per rung is recorded/audited; the
# warm arm must not (see header). Σε <= 1.0 is the "accumulated fidelity loss
# still readable" bound, so the guard never distorts selection here.
function arm(warm::Bool, ph, m, n, betas)
    l = beta_ladder(contractor(ph, m, n), betas, SPARAMS;
        warm_start = warm, max_discarded = warm ? Inf : 1.0)
    clear_memoize_cache()
    l
end

const inst, (M, N, T) = INSTS[SPINS]
const ph = hamiltonian(inst, M, N, T)

@printf("== ladder: %d spins  D=%d  %s  betas=%s  rounds=%d  seed=%d ==\n",
    SPINS, BOND, DEVICE, join(BETAS, ","), ROUNDS, SEED)

# Warm up JIT on the small instance (not recorded): both arms, two rungs, so the
# cold path, the warm-start path and retain_mps snapshots all compile.
let (wi, (wm, wn, wt)) = INSTS[128]
    wph = SPINS == 128 ? ph : hamiltonian(wi, wm, wn, wt)
    wbetas = length(BETAS) > 1 ? BETAS[1:2] : BETAS
    arm(false, wph, wm, wn, wbetas)
    arm(true, wph, wm, wn, wbetas)
end

# First-touch warm-up at the TARGET size (not recorded): the first arm run at a
# new problem size pays one-time costs the small-instance JIT pass cannot cover
# (heap growth to the large working set, the first large Zipper sketches), which
# inflated the first timed arm by ~25% on identical work — rung 1 is cold in
# both arms and must time ~equal for a round to count as clean.
if SPINS != 128
    arm(false, ph, M, N, BETAS[1:1])
end

function cpu_model()
    isfile("/proc/cpuinfo") || return String(Sys.CPU_NAME)
    for line in eachline("/proc/cpuinfo")
        startswith(line, "model name") && return strip(split(line, ":"; limit = 2)[2])
    end
    String(Sys.CPU_NAME)
end

if !isfile(OUT)
    open(OUT, "w") do io
        println(io, "# hardware: $(cpu_model()), $(Sys.CPU_THREADS) logical cores, julia $(VERSION)")
        println(io, "spins,bond,device,round,arm,rung,beta,seed,wall_s,sum_eps,energy")
    end
end

rung_ratios = [Float64[] for _ in BETAS]

for r in 1:ROUNDS
    s = SEED + r
    # Alternate arm order across rounds so neither arm systematically pays for
    # the other's heap/pool state; both arms of a round share one seed.
    order = isodd(r) ? [false, true] : [true, false]
    ladders = Dict{Bool,Any}()
    for warm in order
        Random.seed!(s)
        onGPU && CUDA.seed!(s)
        reclaim!()
        ladders[warm] = arm(warm, ph, M, N, BETAS)
    end
    for warm in (false, true), (k, st) in enumerate(ladders[warm].steps)
        open(OUT, "a") do io
            @printf(io, "%d,%d,%s,%d,%s,%d,%.4f,%d,%.6f,%.6e,%.8f\n",
                SPINS, BOND, DEVICE, r, warm ? "warm" : "cold", k, st.beta, s,
                st.wall_time, st.truncation.discarded_sum, st.energy)
        end
    end
    tc = sum(st.wall_time for st in ladders[false].steps)
    tw = sum(st.wall_time for st in ladders[true].steps)
    @printf("  round %d: cold %.2fs  warm %.2fs  (ladder speed-up %.1f%%)\n", r, tc, tw, 100 * (1 - tw / tc))
    for (k, (c, w)) in enumerate(zip(ladders[false].steps, ladders[true].steps))
        push!(rung_ratios[k], c.wall_time / w.wall_time)
        @printf("    rung %d beta=%-5.4g  cold %.2fs Σε=%.3e E=%.4f | warm%s %.2fs Σε=%.3e E=%.4f\n",
            k, c.beta, c.wall_time, c.truncation.discarded_sum, c.energy,
            w.warm_started ? "" : "(cold)", w.wall_time, w.truncation.discarded_sum, w.energy)
    end
    flush(stdout)
end

# Median per-rung paired cold/warm ratios across rounds -- the quotable numbers.
# Rung 1 is cold in both arms, so its median must sit near 1.00 for the run to
# count as clean; a first round biased by residual warm-up is diluted here by
# the later rounds and the alternating arm order.
@printf("== medians over %d round(s):", ROUNDS)
for (k, rs) in enumerate(rung_ratios)
    @printf("  rung %d cold/warm %.3f (%+.1f%%)", k, median(rs), 100 * (median(rs) - 1))
end
println()
