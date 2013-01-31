<!-- The latest version of this file converted into HTML format can be displayed
online at https://github.com/yast/yast-wagon/blob/Code-11-SP3/doc/Migration_Hooks.md -->

# Migration Hooks

Migration hooks allow to run a custom external script at some point during the
migration process. These scripts allow to handle specific problems which cannot
be handled via usual RPM scripts, or some extra actions might be needed during
migration (not required during normal package update).

The migration hooks are executed with **root** privileges so it is possible to
do any maintenance tasks in the scripts (starting/stopping services, data
backup, data migration, etc...).

The scripts must not be interactive, the stdin and stdout are redirected to
pipes when running in YaST. The X session should not be used as it might not be
available in all cases (e.g. when running in text mode).

## Requirements

Migration hooks are supported in yast2-wagon package version 2.17.34 or higher
(provided as an update for SLES11-SP2, included in SLES11-SP3).

# Hook Script Location and Name Conventions

The scripts are searched in `/var/lib/YaST2/wagon/hooks/` directory.

The expected script name is in format *step_seq_prefix_name*, where

- **step** is a predefined migration step name, describing the current
  migration step.

- **seq** is a sequence number in range 00..99, this allows to set the order in
  which the scripts are executed (it is important to keep the beginning zeros
  for correct sorting!)

- **prefix** should be unique to avoid conflicts (like a name space), use
  package name (if it is part of a package) or your (vendor) name, internet
  domain name, etc... basically anything what can be considered enough unique

- **name** can be any string (just to differ the scripts), some descriptive
  name is recommended

### Example

Example script name (with full path):
`/var/lib/YaST2/wagon/hooks/before_package_migration_00_postgresql_backup`

## Hook Script Exit Value

The script should return exit value 0, if it fails (any non-zero exit value) an
error message is displayed in Wagon and it is possible to restart the script,
ignore the failure (and continue with other scripts) or completely cancel the
hooks for the current step and stage.

## Idempotent Scripts

The hook scripts **can be potentially run more times** (when going back and
forth in the Wagon dialogs, Wagon might restart itself or some steps are
executed multiple times in the migration workflow), the scripts have to cope
with that fact (they can check at the beginning whether they need to do the
action or the action has been already done or they can create a simple
temporary stamp file or otherwise solve multiple runs properly).

# List of Supported Hooks

Some hooks are optional (depend on the previous results or depend on user
selected values). Note that some hooks are called multiple times (e.g.
registration is called before migration and after migration).

Here is the list of supported hooks (step names) in execution order:

- **before_init** - started at the very beginning, (note: it is called again
  after Wagon restart!)
- **before_welcome**, **after_welcome** - started before/after displaying the
  welcome dialog
- **before_registration_check**, **after_registration_check** - Wagon checks
  the registration status (if registration of some products expired the
  migration might fail), if everything is OK no dialog is displayed and Wagon
  automatically continues with the next step
- *(optional, in Patch CD mode only)* - **before_custom_url**,
  **after_custom_url** - repository manager is started
- **before_self_update**, **after_self_update** - called before/after Wagon
  updates itself (to ensure the latest version is used for migration)
- <em>(optional restart - see **Restart Hooks**, Wagon is restarted to run the
  new version, restart is done only when Wagon updated the software stack or
  itself)</em>
- **before_installing_migration_products**,
  **after_installing_migration_products** - called before/after installing the
  migration products
- **before_selecting_migration_source**, **after_selecting_migration_source** -
  Wagon ask the user to migrate via NCC repositories or using a custom
  repository, the next step depends on the user selection
- (either) **before_registration**, **after_registration** - running SUSE
  register (to add migration repositories)
- (or) **before_repo_selection**, **after_repo_selection** - manual repository
  management
- **before_set_migration_repo**, **after_set_migration_repo** - selecting
  migration repositories (full/minimal migration when using NCC) or update
  repository selection (custom repository migration)
- *(the migration proposal is displayed)*
- **before_package_migration** - before package update starts, <u>*after this
  step the real migration starts*</u> and it is not possible to go back to the
  previous state automatically (aborting in this phase results in inconsistent
  (half upgraded) system, manual rollback is needed)
- <em>Restart - See **Restart Hooks**, Wagon is restarted to reload new YaST
  libraries (note: starts the Wagon from migrated system!)</em>
- **before_registration**, **after_registration** - running SUSE register (to
  register updated products)
- **before_congratulate**, **after_congratulate** - before/after Wagon displays
  congratulation dialog after successful migration
- **before_exit** - called just before Wagon exits (always, regardless the
  migration result, also after abort and at restart)

### Abort Hooks

These are special abort hooks which are called when user aborts the migration.
These hooks can be called in any step in the migration workflow therefore the
execution order cannot be guaranteed. The scripts need to check the current
state if they rely on results of other hooks.

- **before_abort** - user confirmed aborting the migration
- **before_abort_rollback**, **after_abort_rollback** - user confirmed rollback
  after abort (reverting to the old products installed before starting
  migration), these hooks are called *after* **before_abort** and skipped when
  user does not confirm rollback.

### Restart Hooks

These hooks are called whenever Wagon restarts itself.

- **before_restart** - Wagon is finishing and will be started again
- **after_restart** - Wagon is restarted, runs the next step in the migration
  workflow

### Recommended hooks

The list of hooks is pretty large, but many of them make sense only in special
cases. In usual use cases these should be preferred:

- Do some action *before* the system is migrated (still running the previous
  version) - use **before_package_migration** hook in this case.

  At this point it is clear than the migration is ready and it is about to
  start, in all steps before it was possible to abort the migration and
  therefore calling the scripts might have not been necessary

- Do some action *after* the system is migrated (the system is running the new
  migrated version, but some things might not be active yet, e.g. updated
  kernel requires reboot, updated services might need restart etc..) - use
  **before_congratulate** or **after_congratulate** hook.

  This can be also used for cleaning up the temporary results of
  **before_package_migration** hook. At this point the migration successfully
  finished.

- Revert changes if migration is aborted - use one of the abort hooks depending
  in which case you need to do the rollback. Keep in mind that the abort hooks
  can be called anytime, so the revert might not be needed (the hook which does
  the changes might not be called yet). The abort hooks need to check the
  current state.


## Obsoleted Hooks

Older versions of Wagon supported only two hook scripts,
`/usr/lib/YaST2/bin/wagon_hook_init` and
`/usr/lib/YaST2/bin/wagon_hook_finish`. The problem was that only one script
could be run as a hook and it was not possible to put hooks directly into RPM
packages because they would conflict.

These old hook scripts are still supported in new Wagon for backward
compatibility, but the new hooks **before_init** and **before_exit** should be
used instead of the obsoleted ones.


