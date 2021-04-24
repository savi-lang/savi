import re

def get_command(debugger, command, result, internal_dict):
  target = debugger.GetSelectedTarget()
  process = target.GetProcess()
  thread = process.GetSelectedThread()
  frame = thread.GetSelectedFrame()

  # Split an expression like '@foo.bar.baz' into ['@', 'foo', 'bar', 'baz']
  names = re.split(r'\.|(?<=\@)(?=.)', command)

  # Get the root value by name, then dig into it using the child field names.
  value = frame.FindVariable(names[0])
  for name in names[1:]:
    # TODO: If the value has an abstract type, we need to use its TYPE field
    # here to .Cast() it to the corresponding concrete type.
    # However it may be difficult to find the appropriate concrete type by name;
    # maybe it will make more sense to leverage the unique type id,
    # and search for a corresponding concrete type with that id in the SBModule.
    value = value.GetChildMemberWithName(name)

  # If this is a pointer type, print its dereferenced content.
  if value.TypeIsPointerType():
    print(value.Dereference())

  # Persist it to a dollar-sign result value, and print that to show it.
  # After this, the lldb user can use the dollar-sign variable in expressions.
  print(value.Persist())
