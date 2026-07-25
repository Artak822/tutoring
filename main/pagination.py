from rest_framework.pagination import PageNumberPagination


class DefaultPagination(PageNumberPagination):
    """Клиент сам выбирает размер страницы: календарю нужен месяц целиком,
    списку платежей — короткие порции."""
    page_size = 20
    page_size_query_param = 'page_size'
    max_page_size = 200
