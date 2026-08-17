# TODO: action-name

<!--
Template README for a new shared action. Copy this folder, then replace every
TODO. Keep the section order: intro, (Requirements if any), Inputs, Outputs,
Usage, Notes.
-->

One-paragraph description of what the action does and when to use it.

## Requirements

<!-- Delete this section if the action has no runner prerequisites. -->

TODO: anything that must exist on the runner (a CLI, a tool, credentials).

## Inputs

| Input     | Required | Default | Description                     |
| --------- | -------- | ------- | ------------------------------- |
| `example` | no       | `''`    | TODO: what this input controls. |

## Outputs

| Output   | Description                     |
| -------- | ------------------------------- |
| `result` | TODO: what this output returns. |

## Usage

```yaml
jobs:
  example:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v7

      - name: TODO
        uses: DataLabHell/ci-actions/TODO-action-name@TODO-action-name/vX.Y.Z
        with:
          example: value
```

## Notes

- TODO: gotchas, credential handling, filter syntax, etc.
