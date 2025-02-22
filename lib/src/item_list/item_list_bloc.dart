import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../filter_conditions/filter_conditions_bloc.dart';
import '../item_source.dart';
import '../search_query/search_query.dart';
import '../utils.dart';

part 'item_list_state.dart';

class ItemListBloc<I extends ItemClassWithAccessor, T extends ItemSourceState>
    extends Bloc<_ItemListEvent, ItemListState> {
  final FilterConditionsBloc _filterConditionsBloc;
  final SearchQueryCubit _searchQueryCubit;
  final Bloc _sourceBloc;
  final List<String> _searchProperties;

  late StreamSubscription _filterConditionsSubscription;
  late StreamSubscription _searchQuerySubscription;
  late StreamSubscription _sourceSubscription;

  ItemListBloc({
    required FilterConditionsBloc filterConditionsBloc,
    required SearchQueryCubit searchQueryCubit,
    required Bloc sourceBloc,
    List<String> searchProperties = const [],
  })  : _filterConditionsBloc = filterConditionsBloc,
        _searchQueryCubit = searchQueryCubit,
        _sourceBloc = sourceBloc,
        _searchProperties = searchProperties,
        super(const NoSourceItems()) {
    _filterConditionsSubscription = _filterConditionsBloc.stream.listen((_) {
      add(_ExternalDataUpdated());
    });

    _searchQuerySubscription = _searchQueryCubit.stream.listen((_) {
      add(_ExternalDataUpdated());
    });

    _sourceSubscription = _sourceBloc.stream.listen((_) {
      add(_ExternalDataUpdated());
    });

    on<_ExternalDataUpdated>((event, emit) {
      if (_filterConditionsBloc.state is! ConditionsInitialized ||
          _sourceBloc.state is! T) {
        return emit(const NoSourceItems());
      }

      final filterResults = _filterSource(_sourceBloc.state.items);
      final searchResults =
          _searchSource(_searchQueryCubit.state, filterResults);

      return emit(searchResults.isEmpty
          ? const ItemEmptyState()
          : ItemResults(searchResults.toList()));
    });
  }

  @override
  Future<void> close() async {
    await _filterConditionsSubscription.cancel();
    await _searchQuerySubscription.cancel();
    await _sourceSubscription.cancel();

    return super.close();
  }

  bool _evaluateFilterCondition(I item, String conditionKey) {
    final parsedConditionKey = splitConditionKey(conditionKey);

    final property = parsedConditionKey[0];
    final itemValue = item[property];
    final targetValue = parsedConditionKey[1];

    if (itemValue is bool) {
      return itemValue.toString() == targetValue.toLowerCase();
    }

    return itemValue == targetValue;
  }

  Iterable<I> _filterSource(List<I> items) {
    final filterState = (_filterConditionsBloc.state as ConditionsInitialized);
    final activeAndConditions = filterState.activeAndConditions;
    final activeOrConditions = filterState.activeOrConditions;

    if (activeAndConditions.isEmpty && activeOrConditions.isEmpty) {
      return items;
    }

    return items.where((item) {
      final hasMatchedOrConditions = activeOrConditions.isEmpty
          ? true
          : activeOrConditions.any(
              (conditionKey) => _evaluateFilterCondition(item, conditionKey));

      if (!hasMatchedOrConditions) {
        return false;
      }

      final hasMatchedAndConditions = activeAndConditions.isEmpty
          ? true
          : activeAndConditions.every(
              (conditionKey) => _evaluateFilterCondition(item, conditionKey));

      return hasMatchedAndConditions && hasMatchedOrConditions;
    });
  }

  Iterable<I> _searchSource(String searchQuery, Iterable<I> items) {
    if (searchQuery.isEmpty) {
      return items;
    }

    return items.where(
      (item) => _searchProperties.any(
        (property) {
          final value = item[property];
          return value is String
              ? value.toLowerCase().contains(searchQuery)
              : false;
        },
      ),
    );
  }
}

class _ExternalDataUpdated extends _ItemListEvent {}

abstract class _ItemListEvent {}
