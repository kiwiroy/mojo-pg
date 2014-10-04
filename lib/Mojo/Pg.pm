package Mojo::Pg;
use Mojo::Base -base;

use Carp 'croak';
use DBI;
use Mojo::Pg::Database;
use Mojo::URL;

has dsn             => 'dbi:Pg:dbname=test';
has max_connections => 5;
has options => sub { {AutoCommit => 1, PrintError => 0, RaiseError => 1} };
has [qw(password username)] => '';

our $VERSION = '0.03';

sub db {
  my $self = shift;

  # Fork safety
  delete @$self{qw(pid queue)} unless ($self->{pid} //= $$) eq $$;

  return Mojo::Pg::Database->new(dbh => $self->_dequeue, pg => $self);
}

sub from_string {
  my ($self, $str) = @_;

  # Protocol
  return $self unless $str;
  my $url = Mojo::URL->new($str);
  croak qq{Invalid PostgreSQL connection string "$str"}
    unless $url->protocol eq 'postgresql';

  # Database
  my $dsn = 'dbi:Pg:dbname=' . $url->path->parts->[0];

  # Host and port
  if (my $host = $url->host) { $dsn .= ";host=$host" }
  if (my $port = $url->port) { $dsn .= ";port=$port" }

  # Username and password
  if (($url->userinfo // '') =~ /^([^:]+)(?::([^:]+))?$/) {
    $self->username($1);
    $self->password($2) if defined $2;
  }

  # Options
  my $hash = $url->query->to_hash;
  @{$self->options}{keys %$hash} = values %$hash;

  return $self->dsn($dsn);
}

sub new { @_ > 1 ? shift->SUPER::new->from_string(@_) : shift->SUPER::new }

sub _dequeue {
  my $self = shift;
  while (my $dbh = shift @{$self->{queue} || []}) { return $dbh if $dbh->ping }
  return DBI->connect(map { $self->$_ } qw(dsn username password options));
}

sub _enqueue {
  my ($self, $dbh) = @_;
  push @{$self->{queue}}, $dbh if $dbh->{Active};
  shift @{$self->{queue}} while @{$self->{queue}} > $self->max_connections;
}

1;

=encoding utf8

=head1 NAME

Mojo::Pg - Mojolicious ♥ PostgreSQL

=head1 SYNOPSIS

  use Mojo::Pg;

  # Create a table
  my $pg = Mojo::Pg->new('postgresql://postgres@/test');
  $pg->db->do('create table names (name varchar(255))');

  # Insert a few rows
  my $db = $pg->db;
  $db->query('insert into names values (?)', 'Sara');
  $db->query('insert into names values (?)', 'Daniel');

  # Select all rows
  say for $db->query('select * from names')
    ->hashes->map(sub { $_->{name} })->each;

  # Select all rows non-blocking
  Mojo::IOLoop->delay(
    sub {
      my $delay = shift;
      $db->query('select * from names' => $delay->begin);
    },
    sub {
      my ($delay, $err, $results) = @_;
      say for $results->hashes->map(sub { $_->{name} })->each;
    }
  )->wait;

=head1 DESCRIPTION

L<Mojo::Pg> is a tiny wrapper around L<DBD::Pg> that makes
L<PostgreSQL|http://www.postgresql.org> a lot of fun to use with the
L<Mojolicious|http://mojolicio.us> real-time web framework.

Database and statement handles are cached automatically. While all I/O
operations are performed blocking, you can wait for long running queries
asynchronously, allowing the L<Mojo::IOLoop> event loop to perform other tasks
in the meantime. Since database connections usually have a very low latency,
this often results in very good performance.

All cached database handles will be reset automatically if a new process has
been forked, this allows multiple processes to share the same L<Mojo::Pg>
object safely.

Note that this whole distribution is EXPERIMENTAL and will change without
warning!

=head1 ATTRIBUTES

L<Mojo::Pg> implements the following attributes.

=head2 dsn

  my $dsn = $pg->dsn;
  $pg     = $pg->dsn('dbi:Pg:dbname=foo');

Data Source Name, defaults to C<dbi:Pg:dbname=test>.

=head2 max_connections

  my $max = $pg->max_connections;
  $pg     = $pg->max_connections(3);

Maximum number of idle database handles to cache for future use, defaults to
C<5>.

=head2 options

  my $options = $pg->options;
  $pg         = $pg->options({AutoCommit => 1});

Options for database handles, defaults to activating C<AutoCommit> as well as
C<RaiseError> and deactivating C<PrintError>.

=head2 password

  my $password = $pg->password;
  $pg          = $pg->password('s3cret');

Database password, defaults to an empty string.

=head2 username

  my $username = $pg->username;
  $pg          = $pg->username('sri');

Database username, defaults to an empty string.

=head1 METHODS

L<Mojo::Pg> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 db

  my $db = $pg->db;

Get L<Mojo::Pg::Database> object for a cached or newly created database
handle.

=head2 from_string

  $pg = $pg->from_string('postgresql://postgres@/test');

Parse configuration from connection string.

  # Just a database
  $pg->from_string('postgresql:///db1');

  # Username and database
  $pg->from_string('postgresql://sri@/db2');

  # Username, password, host and database
  $pg->from_string('postgresql://sri:s3cret@localhost/db3');

  # Username, domain socket and database
  $pg->from_string('postgresql://sri@%2ftmp%2fpg.sock/db4');

  # Username, database and additional options
  $pg->from_string('postgresql://sri@/db5?PrintError=1&RaiseError=0');

=head2 new

  my $pg = Mojo::Pg->new;
  my $pg = Mojo::Pg->new('postgresql://postgres@/test');

Construct a new L<Mojo::Pg> object and parse connection string with
L</"from_string"> if necessary.

  # Customize configuration further
  my $pg = Mojo::Pg->new->dsn('dbi:Pg:service=foo');

=head1 AUTHOR

Sebastian Riedel, C<sri@cpan.org>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Sebastian Riedel.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<https://github.com/kraih/mojo-pg>, L<Mojolicious::Guides>,
L<http://mojolicio.us>.

=cut
