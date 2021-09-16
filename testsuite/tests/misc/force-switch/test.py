"""
Verify the global --force switch is in effect
"""

from drivers.alr import run_alr
from drivers.asserts import assert_match

import re

assert_match('.*interaction flags are:.*force:TRUE.*',
             run_alr('--force', 'version').out,
             flags=re.S)

assert_match('.*interaction flags are:.*force:TRUE.*',
             run_alr('-f', 'version').out,
             flags=re.S)

print('SUCCESS')
