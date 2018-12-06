package JMAP::TestSuite::JMAP::Tester::WebSocket::WithSugar;

use strict;
use warnings;

use Moo;

extends 'JMAP::Tester::WebSocket';

with 'JMAP::TestSuite::JMAP::Tester::WithSugarRole';

1;
