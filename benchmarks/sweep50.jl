# Energy-vs-runtime sweep on the recovered 50x50 (2500-spin) instances.
# Emits CSV incrementally so partial results remain usable.
using SpinGlassPEPS, CUDA
using SpinGlassPEPS.SpinGlassEngine: no_merge
using Base.ScopedValues: with

const OUT = get(ENV, "OUT", "sweep50_cpu.csv")
const NINST = parse(Int, get(ENV, "NINST", "10"))

function solve1(ph, m, n; D, ms, β, onGPU)
    net = PEPSNetwork{SquareSingleNode{GaugesEnergy},Dense,Float64}(m, n, ph, rotation(0))
    ctr = MpsContractor(Zipper, net,
        MpsParameters{Float64}(; bond_dim=D, var_tol=1e-8, num_sweeps=4, tol_SVD=1e-16);
        onGPU=onGPU, beta=β, graduate_truncation=true)
    log = TruncationLog()
    local sol
    t = @elapsed sol = first(with(TRUNCATION_LOG => log) do
        low_energy_spectrum(ctr, SearchParameters(; max_states=ms, cutoff_prob=0.0),
                            no_merge; show_progress=false)
    end)
    st = truncation_stats(log)
    (t, first(sol.energies), st.discarded_sum, st.saturated)
end

function main()
    onGPU = CUDA.functional() && get(ENV,"DEV","cpu") == "gpu"
    dev = onGPU ? "gpu" : "cpu"
    dir = joinpath(pkgdir(SpinGlassPEPS), "benchmark", "instances", "square_50x50")
    m, n, t = 50, 50, 1
    io = open(OUT, "w")
    println(io, "instance,device,series,bond_dim,max_states,beta,time_s,energy,sum_eps,saturated")
    flush(io)
    # warm up JIT on the first instance, cheapest setting
    ph1 = potts_hamiltonian(ising_graph(joinpath(dir,"001.txt")); spectrum=full_spectrum,
              cluster_assignment_rule=super_square_lattice((m,n,t)))
    solve1(ph1, m, n; D=4, ms=16, β=1.0, onGPU=onGPU)

    for k in 1:NINST
        f = joinpath(dir, lpad(k,3,'0') * ".txt")
        ph = potts_hamiltonian(ising_graph(f); spectrum=full_spectrum,
                 cluster_assignment_rule=super_square_lattice((m,n,t)))
        # (1) search-breadth series: the genuine time/quality knob
        for ms in (16, 64, 256, 1024)
            (tt,E,eps,sat) = solve1(ph, m, n; D=8, ms=ms, β=4.0, onGPU=onGPU)
            println(io, "$k,$dev,max_states,8,$ms,4.0,$tt,$E,$eps,$sat"); flush(io)
        end
        # (2) beta series: checks whether the non-monotonicity generalizes
        for β in (2.0, 3.0, 4.0, 6.0, 8.0)
            (tt,E,eps,sat) = solve1(ph, m, n; D=8, ms=256, β=β, onGPU=onGPU)
            println(io, "$k,$dev,beta,8,256,$β,$tt,$E,$eps,$sat"); flush(io)
        end
        @info "instance $k done"
    end
    close(io)
end
main()
