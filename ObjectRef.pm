#!/usr/bin/perl -w
#-*- mode: perl; -*-
use strict;

package ObjectRef;

use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use Carp qw(cluck carp croak confess);

our $curl = "http://www.gtk.org/introspection/c/1.0";
our $global;

sub new {
    my ($c_name) = @_;
    my $class = ref($c_name) || $c_name;
    my $self = {};
    $$self{aliases} = {};
    bless $self, $class;
    return $self;
}

sub set_global {
    $global = shift;
}

sub global {
    return $global;
}

sub is_global {
    my $self = shift;
    return $self == $global;
}

sub exists {
    my ($self, $name) = @_;
    return 0 unless $name;
#    warn "$name exists in registry" if exists $$self{name};
#    warn "$name is an alias for $$self{aliases}{$name}"
#	if exists $$self{aliases}{$name};
    my $exists = (exists $$self{$name} ||
		  exists $$self{aliases}{$name} &&
		  exists $$self{$$self{aliases}{$name}});

    return $global->exists($name) unless $exists || $self == $global;
    return $exists;
}

#Make a unique id, combining an item name with a qualifier and adding
#the current time-value as a seed, then pushing it through MD5 to make
#a nice identifier.
sub make_id {
    my ($self, $name, $qualifier) = @_;
    die "Can't make an id with no name" unless $name;
    my $salt = rand();
    $qualifier = "foo" unless $qualifier;
    return md5_hex("$qualifier.$name.$salt");
}

sub register_object {
    my ($self, $type, $name, $real) = @_;
#    $self->debug(Data::Dumper->Dump([$self], ["ObjectRef"])) if $debug > 5;
    die "Can't make an id with no name" unless $name;
    cluck "Can't make an id with no type" unless $type;
    $$self{$name} = {} unless exists $$self{$name};
    my $entry = $$self{$name};
    if ($$entry{type} && $$entry{type} ne $type &&
	$$entry{type} ne "Temporary") {
	cluck ("Attempt to register existing object $$entry{type}:$name with new type $type");
	return $$entry{id};
    }
    $$entry{real} = $$entry{real} || $real ? 1 : 0;
    $$entry{type} = $type ? $type : "Temporary";
    $$entry{id} = $self->make_id($name, $type) unless $$entry{id};

    return $$entry{id};
}

sub object_id {
    my ($self, $type, $name) = @_;
    die "No $self" unless $self;
    die "Aliases not initialized" unless exists $$self{aliases};
    cluck "No name passed in to object_id" unless $name;

    $name = $$self{aliases}{$name} if exists $$self{aliases}{$name};
    if (exists $$self{$name}) {
	return $$self{$name}{id};
    }
    return $global->object_id($type, $name) if $global->exists($name);
    return $self->register_object($type, $name);
}

sub object_type {
    my ($self, $name) = @_;
    return undef unless $name;
    $name = $$self{aliases}{$name} if exists $$self{aliases}{$name};
    return $global->object_type($name)
	unless exists $$self{$name} || $self == $global;
    return undef unless exists $$self{$name};
    return $$self{$name}{type};
}

sub register_alias {
    my ($self, $element) = @_;
    my $name = $element->getAttribute("name") or return;
    my $typeattr = $element->getAttributeNS($curl, "type") or return;

    $$self{aliases}{$typeattr} = $name;
}

sub get_unregistered {
    my ($self) = @_;
    my $list = [];
    foreach my $name (keys %$self) {
	next if $$self{$name}{real};
	next if $name eq "aliases";
	my $hash = $$self{$name};
	$$hash{name} = $name;
	push @$list, $hash;
    }
    return $list;
}

sub reregister_global {
    my ($self, $name) = @_;
    croak "Don't call reregister_global on global" if $global == $self;
    croak "$name already registered in global" if $global->exists($name);
    if (exists $$self{aliases}{$name}) {
	$name = $$self{aliases}{$name};
	croak "Real name $name already exists in global, aliased by $name"
	    if $global->exists($name);
    }
    $$global{$name} = $$self{$name};
    delete $$self{$name};
    my @aliases;
    for my $alias (keys %{$$self{aliases}}) {
	push @aliases, $alias if $$self{aliases}{$alias} eq $name;
    }
    for my $alias (@aliases) {
	if (exists $$global{aliases}{$alias}) {
	    carp "Alias $alias already exists in global, skipping";
	    delete $$self{aliases};
	    next;
	}
	$$global{aliases}{$alias} = $name;
	delete $$self{$alias};
    }
}

sub change_type {
    my ($self, $name, $new_type) = @_;
    $$self{$name}{type} = $new_type;
}
1;
