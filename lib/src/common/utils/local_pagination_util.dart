/// Infers "has more" from page fullness: a full page means another page
/// probably exists; a short page is the last one.
class LocalPaginationUtil {
  const LocalPaginationUtil();

  static const int defaultLimit = 30;

  bool checkIsListHasMorePageBool<T>({required List<T> list, int? limitInPage}) =>
      list.length >= (limitInPage ?? defaultLimit);
}
