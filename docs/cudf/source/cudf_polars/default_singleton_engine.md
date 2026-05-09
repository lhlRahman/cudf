(cudf-polars-default-singleton-engine)=
# DefaultSingletonEngine

{class}`~cudf_polars.experimental.rapidsmpf.frontend.default_singleton_engine.DefaultSingletonEngine`
is a process-wide singleton specialization of
{class}`~cudf_polars.experimental.rapidsmpf.frontend.spmd.SPMDEngine` that backs the streaming
executor when the user has *not* constructed an engine explicitly. At most one live instance
exists per process; it is created lazily on first use and torn down at interpreter exit.

```{important}
For any non-trivial workflow, construct an engine explicitly — for example
{meth}`RayEngine.from_options(...) <cudf_polars.experimental.rapidsmpf.frontend.ray.RayEngine.from_options>`
or {meth}`SPMDEngine.from_options(...) <cudf_polars.experimental.rapidsmpf.frontend.spmd.SPMDEngine.from_options>`.
The default singleton uses no-argument defaults; if you need to tune anything — for example
`spill_to_pinned_memory=True` for spill-heavy workloads — you must construct an engine
yourself. See {doc}`usage` and {doc}`options`.
```

## What you get without an explicit engine

When the user just writes:

```python
import polars as pl

result = (
    pl.scan_parquet("/data/*.parquet")
      .group_by("customer_id")
      .agg(pl.col("amount").sum())
      .collect(engine="gpu")
)
```

cudf-polars uses
{class}`~cudf_polars.experimental.rapidsmpf.frontend.default_singleton_engine.DefaultSingletonEngine`
under the hood. No cluster is set up, the rapidsmpf `Context` is bootstrapped on first use,
and subsequent `.collect()` calls in the same process reuse it.

## Explicit handle

If you genuinely want the singleton — for example in tests or scripts that need to call
`.shutdown()` deterministically — you can obtain it via the factory:

```python
from cudf_polars.experimental.rapidsmpf.frontend.default_singleton_engine import (
    DefaultSingletonEngine,
)

engine = DefaultSingletonEngine.create_or_get()
result = query.collect(engine=engine)
```

`create_or_get()` is idempotent: calling it again returns the same instance.

For anything beyond defaults, prefer an explicit engine — see {doc}`usage`.

## Lifecycle

The singleton is bootstrapped once per process. The rapidsmpf `Context`, RMM adaptor, and
Python thread-pool executor are reused across every `.collect()` call.

Shutdown is automatic: the engine registers an `atexit` hook that tears it down at interpreter
exit. To shut it down explicitly (for example to release resources before constructing a
multi-GPU engine), call the static method:

```python
from cudf_polars.experimental.rapidsmpf.frontend.default_singleton_engine import (
    DefaultSingletonEngine,
)

DefaultSingletonEngine.shutdown()
```

`shutdown()` is idempotent — calling it twice is safe — and a no-op if no live engine exists.

## Mutual exclusion with explicit engines

`DefaultSingletonEngine`, {class}`~cudf_polars.experimental.rapidsmpf.frontend.ray.RayEngine`,
{class}`~cudf_polars.experimental.rapidsmpf.frontend.dask.DaskEngine`, and
{class}`~cudf_polars.experimental.rapidsmpf.frontend.spmd.SPMDEngine` cannot coexist in the same
process. Concretely:

- Constructing `RayEngine` / `DaskEngine` / `SPMDEngine` while the singleton is alive raises
  `RuntimeError`.
- `DefaultSingletonEngine.create_or_get()` raises `RuntimeError` if any explicit streaming
  engine is alive.

Recommended pattern: pick one engine for the lifetime of the program. If you need to switch,
shut down the active engine first:

```python
DefaultSingletonEngine.shutdown()
explicit_engine = SPMDEngine.from_options(opts)
```

## No options

`DefaultSingletonEngine.create_or_get()` takes no arguments. To tune `StreamingOptions` —
e.g. `spill_to_pinned_memory`, `fallback_mode`, `max_rows_per_partition`, or any rapidsmpf
runtime knob — construct an explicit
{class}`~cudf_polars.experimental.rapidsmpf.frontend.ray.RayEngine`,
{class}`~cudf_polars.experimental.rapidsmpf.frontend.dask.DaskEngine`, or
{class}`~cudf_polars.experimental.rapidsmpf.frontend.spmd.SPMDEngine` via `from_options(...)`.
See {doc}`options` for the available fields.
