(cudf-polars-engines)=
# Engines

## What is an engine?

`cudf-polars` executes Polars `LazyFrame` queries on GPU. You select GPU execution by passing an
`engine=` argument to `.collect()` or `.sink_*()`. The `engine` you pass decides *how* the
query runs: whether it streams through partitioned inputs or fits everything in device memory,
whether it runs in-process or distributes work across a cluster of GPU workers, and which
cluster backend coordinates those workers.

## Execution modes

### Streaming

Streaming engines partition their inputs (Parquet files or in-memory `DataFrame`s) and process
those partitions through the query graph in chunks. This lets queries scale past device memory
and (on Ray, Dask, and SPMD) across multiple GPUs and multiple nodes. cudf-polars' streaming
executor is its own GPU implementation, but conceptually parallels
[Polars' CPU streaming engine](https://docs.pola.rs/user-guide/concepts/streaming/): the same
partition-and-stream model, just on the GPU.

All four cudf-polars engines use this same streaming executor:
{class}`~cudf_polars.experimental.rapidsmpf.frontend.ray.RayEngine`,
{class}`~cudf_polars.experimental.rapidsmpf.frontend.dask.DaskEngine`,
{class}`~cudf_polars.experimental.rapidsmpf.frontend.spmd.SPMDEngine`, and the implicit
{class}`~cudf_polars.experimental.rapidsmpf.frontend.default_singleton_engine.DefaultSingletonEngine`.
They differ only in how their GPU worker(s) are provisioned.
{class}`~cudf_polars.experimental.rapidsmpf.frontend.ray.RayEngine` with no arguments uses every
GPU visible to the process, so on a single node with N GPUs it runs the query on all N of them
without any extra configuration. Launching a multi-node cluster simply means pointing the
engine at that cluster; the user-facing code is the same.

### In-memory

The in-memory engine (`engine="in-memory"` or `engine=pl.GPUEngine(executor="in-memory")`) is
the only non-streaming path. It runs the query on a single GPU, materializing intermediates in
device memory. Use it for small queries (data that fits in device memory), debugging, or when
you specifically need `LazyFrame.profile` support (see {doc}`profiling`). For production
workloads on any nontrivial dataset, use a streaming engine. See {doc}`in_memory_engine` for
details.

```{note}
`engine="gpu"` and `engine=pl.GPUEngine()` no longer select the in-memory path. They use the
implicit `DefaultSingletonEngine` (streaming, single-GPU). To pick the in-memory engine you
must say so explicitly.
```

## Cluster backends

The four streaming engines differ only in how the GPU worker(s) are provisioned and
coordinated:

| Engine                                                                                                       | Cluster model                                                       | Extra runtime dependency | Typical use                                                                       |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------- | ------------------------ | --------------------------------------------------------------------------------- |
| {class}`~cudf_polars.experimental.rapidsmpf.frontend.ray.RayEngine`                                          | Single-client driver; one Ray actor per GPU                         | [Ray][ray-docs]          | Works from a laptop to a cloud cluster. No separate cluster setup needed.         |
| {class}`~cudf_polars.experimental.rapidsmpf.frontend.dask.DaskEngine`                                        | Single-client driver; one Dask worker per GPU                       | [Dask distributed][dask] | Teams with an existing Dask deployment or a preferred Dask launcher.              |
| {class}`~cudf_polars.experimental.rapidsmpf.frontend.spmd.SPMDEngine`                                        | Same script runs once per GPU, joined by a communicator             | UCXX (under `rrun`)      | HPC / SPMD launchers such as `rrun`. Single-rank mode needs no cluster at all.    |
| {class}`~cudf_polars.experimental.rapidsmpf.frontend.default_singleton_engine.DefaultSingletonEngine`        | Implicit process-wide singleton on one GPU; no cluster              | None                     | Default when `engine="gpu"`. Short scripts and notebooks. No options.   |

All four approaches use the same execution model under the hood, so which to select depends
on your preferred deployment method, not performance tradeoffs. For any non-trivial workflow,
construct one of the first three engines explicitly (see {doc}`usage`); the
`DefaultSingletonEngine` is a convenience and accepts no options, so it cannot be tuned. See
{doc}`default_singleton_engine` for details.

## Where to go next

- {doc}`usage` — tutorial that walks through running your first GPU query end-to-end.
- {doc}`other_engines` — per-engine reference pages for DaskEngine and SPMDEngine.
- {doc}`options` — the `StreamingOptions` configuration object and every field it surfaces.

[ray-docs]: https://docs.ray.io/
[dask]: https://distributed.dask.org/
