#!/bin/bash
#SBATCH --job-name=stress-ng-validate
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=64
#SBATCH --time=02:30:00
#SBATCH --output=logfiles/output/stress-ng_%j.out
#SBATCH --error=logfiles/error/stress-ng_%j.err
#SBATCH --hint=nomultithread
#SBATCH --threads-per-core=1
#SBATCH --account=rc_ops
#SBATCH --partition=cpu0

set -euo pipefail

mkdir -p logfiles/output logfiles/error results

: "${SLURM_JOB_ID:?SLURM_JOB_ID is not set}"
: "${SLURM_JOB_NUM_NODES:?SLURM_JOB_NUM_NODES is not set}"
: "${SLURM_CPUS_ON_NODE:?SLURM_CPUS_ON_NODE is not set}"

module purge
module load gcc/12.3
module load stress-ng/0.17.00

STRESS_TIMEOUT="${STRESS_TIMEOUT:-60m}"
VM_BYTES="${VM_BYTES:-50%}"
CPU_METHOD="${CPU_METHOD:-all}"
VM_METHOD="${VM_METHOD:-all}"

# Validation threshold
MIN_CPU_BOGO_OPS_PER_SEC="${MIN_CPU_BOGO_OPS_PER_SEC:-1000}"

CPU_COUNT="${SLURM_CPUS_ON_NODE}"
RAW_LOG="results/stress-ng_${SLURM_JOB_ID}.log"
SUMMARY_LOG="results/stress-ng_${SLURM_JOB_ID}.summary"

echo "========================================"
echo "Starting stress-ng validation job"
echo "Job ID          : ${SLURM_JOB_ID}"
echo "Job Name        : ${SLURM_JOB_NAME:-unknown}"
echo "Partition       : ${SLURM_JOB_PARTITION:-unknown}"
echo "Node Count      : ${SLURM_JOB_NUM_NODES}"
echo "Node List       : ${SLURM_JOB_NODELIST:-unknown}"
echo "Host            : $(hostname)"
echo "CPUs on Nodes   : ${SLURM_CPUS_ON_NODE}"
echo "Start Time      : $(date)"
echo "Stress Timeout  : ${STRESS_TIMEOUT}"
echo "VM Bytes        : ${VM_BYTES}"
echo "CPU Method      : ${CPU_METHOD}"
echo "VM Method       : ${VM_METHOD}"
echo "Min CPU BogoOps : ${MIN_CPU_BOGO_OPS_PER_SEC}"
echo "========================================"

run_stress_ng() {
    srun --nodes="${SLURM_JOB_NUM_NODES}" \
         --ntasks-per-node=1 \
         --exclusive \
         --cpu-bind=cores \
         stress-ng --cpu "$CPU_COUNT" \
                   --cpu-method "$CPU_METHOD" \
                   --vm 1 \
                   --vm-bytes "$VM_BYTES" \
                   --vm-method "$VM_METHOD" \
                   --timeout "$STRESS_TIMEOUT" \
                   --verbose \
                   --verify \
                   --metrics 2>&1 | tee "$RAW_LOG"
}

parse_failed_count() {
    grep -E "failed:" "$RAW_LOG" | tail -n 1 | awk -F'failed: ' '{print $2}' | awk '{print $1}'
}

parse_untrustworthy_count() {
    grep -E "metrics untrustworthy:" "$RAW_LOG" | tail -n 1 | awk -F'metrics untrustworthy: ' '{print $2}' | awk '{print $1}'
}

parse_cpu_bogo_ops_per_sec() {
    awk '
        /stress-ng: metrc:/ && $0 ~ / cpu / {
            for (i = 1; i <= NF; i++) {
                if ($i == "cpu") {
                    print $(i+5)
                    exit
                }
            }
        }
    ' "$RAW_LOG"
}

validate_results() {
    local failed_count
    local untrustworthy_count
    local cpu_bogo
    local rc=0

    failed_count="$(parse_failed_count)"
    untrustworthy_count="$(parse_untrustworthy_count)"
    cpu_bogo="$(parse_cpu_bogo_ops_per_sec)"

    failed_count="${failed_count:-999999}"
    untrustworthy_count="${untrustworthy_count:-999999}"
    cpu_bogo="${cpu_bogo:-0}"

    {
        echo "Validation Summary"
        echo "=================="
        echo "Node                 : ${SLURM_JOB_NODELIST:-unknown}"
        echo "Host                 : $(hostname)"
        echo "Failed count         : ${failed_count}"
        echo "Untrustworthy metrics: ${untrustworthy_count}"
        echo "CPU bogo ops/s       : ${cpu_bogo}"
        echo "Minimum CPU bogo/s   : ${MIN_CPU_BOGO_OPS_PER_SEC}"
    } | tee "$SUMMARY_LOG"

    if [[ "$failed_count" -ne 0 ]]; then
        echo "FAIL: failed count is not zero" | tee -a "$SUMMARY_LOG"
        rc=1
    fi

    if [[ "$untrustworthy_count" -ne 0 ]]; then
        echo "FAIL: untrustworthy metrics count is not zero" | tee -a "$SUMMARY_LOG"
        rc=1
    fi

    awk -v actual="$cpu_bogo" -v minimum="$MIN_CPU_BOGO_OPS_PER_SEC" '
        BEGIN {
            if ((actual + 0) < (minimum + 0)) exit 1
            exit 0
        }
    ' || {
        echo "FAIL: CPU bogo ops/s is below threshold" | tee -a "$SUMMARY_LOG"
        rc=1
    }

    if [[ "$rc" -eq 0 ]]; then
        echo "PASS: node validation passed" | tee -a "$SUMMARY_LOG"
    else
        echo "FAIL: node validation failed" | tee -a "$SUMMARY_LOG"
    fi

    return "$rc"
}

if run_stress_ng; then
    echo "stress-ng run completed, validating output..."
else
    status=$?
    echo "FAIL: stress-ng execution failed with exit code ${status}" | tee "$SUMMARY_LOG"
    exit "$status"
fi

if validate_results; then
    echo "Validation PASSED"
    exit 0
else
    echo "Validation FAILED"
    exit 1
fi
